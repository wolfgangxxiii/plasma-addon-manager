//! User-level automation adapted from the working Bazzite and Debian GUIs.
//! This edition owns *different* systemd unit names, so existing schedules
//! are never overwritten or disabled without explicit migration consent.

use crate::{
    executable_on_path, find_plasmoid_updater, is_executable, read_distribution, updater_installer,
    updater_path, DistributionFamily,
};
use anyhow::{anyhow, bail, ensure, Context, Result};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::Duration;
use toml_edit::{value, Array, DocumentMut};

pub const SERVICE: &str = "plasma-addon-manager.service";
pub const TIMER: &str = "plasma-addon-manager.timer";
pub const AGENT: &str = "plasma-addon-manager-agent";
const MANAGED: &str = "# Managed by Plasma Addon Manager 0.3+";
const LEGACY_TIMERS: &[&str] = &["plasmoid-updater.timer", "bazzite-plasmoid-updater.timer"];
const RETRY_DELAYS: &[u64] = &[3, 9];

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct Settings {
    pub automatic: bool,
    pub auto_update_tool: bool,
    pub frequency_hours: u8,
    pub restart_plasma: bool,
    pub notify_on_success: bool,
    pub notify_on_error: bool,
    pub excluded_packages: Vec<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            automatic: true,
            auto_update_tool: true,
            frequency_hours: 24,
            restart_plasma: false,
            notify_on_success: false,
            notify_on_error: true,
            excluded_packages: Vec::new(),
        }
    }
}

impl Settings {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            matches!(self.frequency_hours, 6 | 12 | 24),
            "Choose 6, 12 or 24 hours"
        );
        ensure!(
            self.excluded_packages.len() <= 100,
            "Too many excluded packages (max 100)"
        );
        for name in &self.excluded_packages {
            ensure!(
                !name.trim().is_empty() && name.len() <= 120,
                "Invalid excluded package name"
            );
            ensure!(
                !name.chars().any(char::is_control),
                "Control characters are not allowed in exclusions"
            );
        }
        Ok(())
    }

    pub fn path(home: &Path) -> PathBuf {
        home.join(".config/plasma-addon-manager/settings.toml")
    }

    pub fn load(home: &Path) -> Result<Self> {
        // Import settings of the two working programs on the first run.
        // Never edit or remove their settings files.
        let path = Self::path(home);
        let candidates = [
            path,
            home.join(".config/bazzite-plasmoid-updater-gui/settings.toml"),
            home.join(".config/deb-plasmoid-updater-gui/settings.toml"),
        ];
        let mut settings = Self::default();
        let mut loaded_from_other_app = false;
        for (index, candidate) in candidates.iter().enumerate() {
            if !candidate.exists() {
                continue;
            }
            let content = fs::read_to_string(candidate)
                .with_context(|| format!("Cannot read {}", candidate.display()))?;
            settings = toml::from_str(&content)
                .with_context(|| format!("Invalid settings in {}", candidate.display()))?;
            loaded_from_other_app = index != 0;
            break;
        }
        if loaded_from_other_app || candidates.iter().all(|path| !path.exists()) {
            // An upstream exclusion list may have been created manually.
            let config = upstream_config(home);
            if config.is_file() && settings.excluded_packages.is_empty() {
                let text = fs::read_to_string(&config)?;
                let doc: DocumentMut = text
                    .parse()
                    .context("Invalid existing plasmoid-updater TOML")?;
                if let Some(excludes) = doc
                    .get("excluded_packages")
                    .and_then(|entry| entry.as_array())
                {
                    settings.excluded_packages = excludes
                        .iter()
                        .map(|entry| {
                            entry
                                .as_str()
                                .map(str::to_owned)
                                .ok_or_else(|| anyhow!("Invalid excluded_packages entry"))
                        })
                        .collect::<Result<Vec<_>>>()?;
                }
            }
        }
        settings.validate()?;
        Ok(settings)
    }

    fn save(&self, home: &Path) -> Result<()> {
        self.validate()?;
        atomic_write(&Self::path(home), toml::to_string_pretty(self)?.as_bytes())
    }
}

pub fn home() -> Result<PathBuf> {
    env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| anyhow!("HOME is unavailable"))
}

fn upstream_config(home: &Path) -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config"))
        .join("plasmoid-updater.toml")
}

fn units_dir(home: &Path) -> PathBuf {
    home.join(".config/systemd/user")
}

fn agent_path(home: &Path) -> PathBuf {
    home.join(".local/bin").join(AGENT)
}

fn unit_is_managed(path: &Path) -> bool {
    fs::read_to_string(path).is_ok_and(|content| content.starts_with(MANAGED))
}

fn user_unit_state(name: &str, query: &str) -> bool {
    Command::new("systemctl")
        .args(["--user", query, name])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
}

fn unit_property(name: &str, property: &str) -> Option<String> {
    let result = Command::new("systemctl")
        .args(["--user", "show", name, "--property", property, "--value"])
        .stdin(Stdio::null())
        .output()
        .ok()?;
    result
        .status
        .success()
        .then(|| String::from_utf8_lossy(&result.stdout).trim().to_owned())
}

#[derive(Debug, Serialize)]
pub struct DashboardState {
    pub distribution: String,
    pub updater_version: Option<String>,
    pub bsdtar_available: bool,
    pub agent_version: Option<String>,
    pub agent_needs_repair: bool,
    pub agent_managed: bool,
    pub timer_active: bool,
    pub timer_enabled: bool,
    pub last_failed: bool,
    pub next_run: String,
    pub last_result: String,
    pub conflicting_timers: Vec<String>,
    pub automatic_configured: bool,
    pub frequency_hours: u8,
}

fn parse_version(raw: &str, prefix: &str) -> Option<String> {
    // plasmoid-updater 0.2.1 prints its GPL licensing text after the first
    // line. Only the version token belongs on the dashboard's small card.
    raw.lines().find_map(|line| {
        let version = line
            .trim()
            .strip_prefix(prefix)?
            .split_whitespace()
            .next()?;
        version
            .trim_start_matches('v')
            .chars()
            .next()
            .filter(char::is_ascii_digit)
            .map(|_| version.trim_start_matches('v').to_owned())
    })
}

fn version_of(path: &Path, prefix: &str) -> Option<String> {
    let output = Command::new(path)
        .arg("--version")
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    parse_version(&String::from_utf8(output.stdout).ok()?, prefix)
}

fn service_result_failed(result: &str) -> bool {
    !matches!(result, "" | "unknown" | "success")
}

pub fn dashboard_state() -> Result<DashboardState> {
    let home = home()?;
    let updater_version =
        find_plasmoid_updater().and_then(|path| version_of(&path, "plasmoid-updater "));
    let agent_version = version_of(&agent_path(&home), "plasma-addon-manager-agent ");
    let agent_managed = unit_is_managed(&units_dir(&home).join(SERVICE))
        && unit_is_managed(&units_dir(&home).join(TIMER));
    let last_result = unit_property(SERVICE, "Result").unwrap_or_else(|| "unknown".to_owned());
    let configured = Settings::path(&home).is_file();
    let frequency_hours = Settings::load(&home)
        .map(|settings| settings.frequency_hours)
        .unwrap_or(24);
    Ok(DashboardState {
        distribution: read_distribution().pretty_name,
        updater_version,
        bsdtar_available: service_bsdtar_exists(&home),
        agent_needs_repair: agent_managed
            && agent_version.as_deref() != Some(env!("CARGO_PKG_VERSION")),
        agent_version,
        agent_managed,
        timer_active: user_unit_state(TIMER, "is-active"),
        timer_enabled: user_unit_state(TIMER, "is-enabled"),
        last_failed: service_result_failed(&last_result),
        next_run: unit_property(TIMER, "NextElapseUSecRealtime").unwrap_or_default(),
        last_result,
        conflicting_timers: legacy_active()
            .iter()
            .map(|timer| (*timer).to_owned())
            .collect(),
        automatic_configured: configured,
        frequency_hours,
    })
}

/// Read-only test of the *saved* configuration, agent and systemd user timer.
/// Unlike an updater dry-run, this verifies that unattended updates can run.
pub fn test_configuration() -> Result<()> {
    let home = home()?;
    ensure!(
        Settings::path(&home).is_file(),
        "Save your automation settings before testing"
    );
    let settings = Settings::load(&home)?;
    settings.validate()?;
    let updater = find_plasmoid_updater().context("Install plasmoid-updater first")?;
    println!("✓ Updater: {}", updater.display());
    ensure!(
        service_bsdtar_exists(&home),
        "bsdtar is not available to the systemd service"
    );
    println!("✓ bsdtar is available to the background service.");
    ensure!(
        executable_on_path("kpackagetool6").is_some()
            || is_executable(Path::new("/usr/bin/kpackagetool6")),
        "kpackagetool6 is missing"
    );
    println!("✓ KDE package tool is available.");
    let config = upstream_config(&home);
    ensure!(
        config.is_file(),
        "No upstream configuration: {}",
        config.display()
    );
    let _: DocumentMut = fs::read_to_string(&config)?
        .parse()
        .context("Invalid plasmoid-updater TOML")?;
    println!("✓ Upstream configuration is valid.");

    if settings.automatic {
        ensure!(
            unit_is_managed(&units_dir(&home).join(SERVICE)),
            "Managed systemd service is missing"
        );
        ensure!(
            unit_is_managed(&units_dir(&home).join(TIMER)),
            "Managed systemd timer is missing"
        );
        ensure!(
            version_of(&agent_path(&home), "plasma-addon-manager-agent ").as_deref()
                == Some(env!("CARGO_PKG_VERSION")),
            "Agent is missing or outdated; click Repair agent"
        );
        let service = fs::read_to_string(units_dir(&home).join(SERVICE))?;
        ensure!(
            service.contains(&format!("ExecStart=%h/.local/bin/{AGENT} run")),
            "Service points to the wrong agent"
        );
        let timer = fs::read_to_string(units_dir(&home).join(TIMER))?;
        ensure!(
            timer.contains(&format!(
                "OnCalendar={}",
                timer_schedule(settings.frequency_hours)?
            )),
            "Timer interval does not match saved settings"
        );
        ensure!(
            user_unit_state(TIMER, "is-enabled") && user_unit_state(TIMER, "is-active"),
            "Scheduled updates are not enabled and active"
        );
        ensure!(
            unit_property(SERVICE, "LoadState").as_deref() == Some("loaded")
                && unit_property(TIMER, "LoadState").as_deref() == Some("loaded"),
            "Systemd did not load the new units"
        );
        ensure!(
            legacy_active().is_empty(),
            "An older updater schedule is still active; migration requires consent"
        );
        println!(
            "✓ Agent v{} and scheduled timer are ready.",
            env!("CARGO_PKG_VERSION")
        );
        println!(
            "Next update: {}",
            unit_property(TIMER, "NextElapseUSecRealtime").unwrap_or_default()
        );
    } else {
        ensure!(
            !user_unit_state(TIMER, "is-enabled") && !user_unit_state(TIMER, "is-active"),
            "The timer is still active even though automatic updates are disabled"
        );
        println!("✓ Automatic updates are correctly disabled.");
    }
    println!("Checking KDE Store read-only (no add-ons will be changed)…");
    io::stdout().flush()?;
    let checked = crate::addons::updates()?;
    println!(
        "✓ Read-only check completed: {} available updates, {} issues.",
        checked.available.len(),
        checked.issues.len()
    );
    println!("✓ Saved automation configuration is valid.");
    Ok(())
}

pub fn status() {
    let home = match home() {
        Ok(path) => path,
        Err(error) => {
            eprintln!("{error:#}");
            return;
        }
    };
    println!("Plasma Addon Manager — automatic updates");
    println!("Timer: {TIMER}");
    println!("Enabled: {}", user_unit_state(TIMER, "is-enabled"));
    println!("Active: {}", user_unit_state(TIMER, "is-active"));
    println!(
        "Managed service: {}",
        unit_is_managed(&units_dir(&home).join(SERVICE))
    );
    println!(
        "Agent: {}",
        if is_executable(&agent_path(&home)) {
            "installed"
        } else {
            "missing"
        }
    );
    println!(
        "Next run: {}",
        unit_property(TIMER, "NextElapseUSecRealtime").unwrap_or_else(|| "unknown".into())
    );
    println!(
        "Last result: {}",
        unit_property(SERVICE, "Result").unwrap_or_else(|| "unknown".into())
    );
    for name in LEGACY_TIMERS {
        if user_unit_state(name, "is-enabled") || user_unit_state(name, "is-active") {
            println!("! Older active timer: {name}. Migration consent required.");
        }
    }
}

fn output(command: &mut Command) -> Result<Output> {
    let result = command
        .stdin(Stdio::null())
        .output()
        .context("Unable to execute system command")?;
    ensure!(
        result.status.success(),
        "{}: {}",
        result.status,
        String::from_utf8_lossy(&result.stderr).trim()
    );
    Ok(result)
}

fn systemctl(args: &[&str]) -> Result<()> {
    output(Command::new("systemctl").arg("--user").args(args))?;
    Ok(())
}

pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let dir = path.parent().context("Invalid destination")?;
    fs::create_dir_all(dir)?;
    let mut staged = tempfile::NamedTempFile::new_in(dir)?;
    staged.write_all(bytes)?;
    staged.flush()?;
    staged
        .persist(path)
        .with_context(|| format!("Unable to write {}", path.display()))?;
    Ok(())
}

/// Keep the OS-level lock handle alive for the entire modifying operation.
/// This serializes manual GUI updates and the unattended systemd agent.
pub fn update_lock() -> Result<File> {
    let path = home()?.join(".local/state/plasma-addon-manager/update.lock");
    fs::create_dir_all(path.parent().context("Invalid lock path")?)?;
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)?;
    file.try_lock_exclusive()
        .context("Another Plasma Addon Manager update is already running")?;
    Ok(file)
}

#[derive(Debug)]
struct Snapshot {
    path: PathBuf,
    previous: Option<(Vec<u8>, u32)>,
}

fn snapshot_files(paths: &[PathBuf]) -> Result<Vec<Snapshot>> {
    paths
        .iter()
        .map(|path| {
            let previous = if fs::symlink_metadata(path).is_ok() {
                let bytes = fs::read(path)?;
                let mode = fs::metadata(path)?.permissions().mode();
                Some((bytes, mode))
            } else {
                None
            };
            Ok(Snapshot {
                path: path.clone(),
                previous,
            })
        })
        .collect()
}

fn restore_files(snapshots: &[Snapshot]) {
    for snapshot in snapshots {
        let result: Result<()> = (|| match &snapshot.previous {
            Some((bytes, mode)) => {
                atomic_write(&snapshot.path, bytes)?;
                fs::set_permissions(&snapshot.path, fs::Permissions::from_mode(*mode))?;
                Ok(())
            }
            None if fs::symlink_metadata(&snapshot.path).is_ok() => {
                fs::remove_file(&snapshot.path)?;
                Ok(())
            }
            None => Ok(()),
        })();
        if let Err(error) = result {
            eprintln!("Could not restore {}: {error:#}", snapshot.path.display());
        }
    }
}

fn timer_schedule(hours: u8) -> Result<&'static str> {
    match hours {
        6 => Ok("*-*-* 00,06,12,18:00:00"),
        12 => Ok("*-*-* 00,12:00:00"),
        24 => Ok("*-*-* 04:00:00"),
        _ => bail!("Unsupported interval: {hours}"),
    }
}

fn upstream_document(config: &Path, settings: &Settings) -> Result<DocumentMut> {
    let old = if config.is_file() {
        fs::read_to_string(config)?
    } else {
        String::new()
    };
    let mut doc: DocumentMut = old
        .parse()
        .context("Cannot parse existing plasmoid-updater settings")?;
    let mut excluded = Array::new();
    for package in &settings.excluded_packages {
        excluded.push(package.as_str());
    }
    // Keep all unrelated upstream settings untouched.
    doc["excluded_packages"] = value(excluded);
    Ok(doc)
}

fn install_agent(home: &Path) -> Result<()> {
    let source = env::current_exe()?
        .parent()
        .context("Cannot locate app helper")?
        .join(AGENT);
    ensure!(source.is_file(), "Missing {AGENT} inside this AppImage");
    let target = agent_path(home);
    let dir = target.parent().context("Invalid agent path")?;
    fs::create_dir_all(dir)?;
    let mut staged = tempfile::NamedTempFile::new_in(dir)?;
    io::copy(&mut File::open(&source)?, &mut staged)?;
    staged
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o755))?;
    // Close the writer before verifying that the agent can execute.
    let staged = staged.into_temp_path();
    let staged_path: &Path = staged.as_ref();
    let check = Command::new(staged_path)
        .arg("--version")
        .stdin(Stdio::null())
        .output()?;
    ensure!(
        check.status.success()
            && String::from_utf8_lossy(&check.stdout).starts_with("plasma-addon-manager-agent "),
        "Bundled agent failed validation"
    );
    staged.persist(target)?;
    println!("✓ Agent installed in ~/.local/bin.");
    Ok(())
}

fn service_text() -> String {
    format!("{MANAGED}\n[Unit]\nDescription=Update user KDE Store add-ons with Plasma Addon Manager\n\n[Service]\nType=oneshot\nEnvironment=PATH=%h/.local/bin:/home/linuxbrew/.linuxbrew/opt/libarchive/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin\nExecStart=%h/.local/bin/{AGENT} run\nNice=10\nIOSchedulingClass=idle\n")
}

fn timer_text(hours: u8) -> Result<String> {
    Ok(format!("{MANAGED}\n[Unit]\nDescription=Schedule Plasma Addon Manager updates\n\n[Timer]\nOnCalendar={}\nRandomizedDelaySec=20min\nPersistent=true\nUnit={SERVICE}\n\n[Install]\nWantedBy=timers.target\n", timer_schedule(hours)?))
}

fn legacy_active() -> Vec<&'static str> {
    LEGACY_TIMERS
        .iter()
        .copied()
        .filter(|timer| user_unit_state(timer, "is-enabled") || user_unit_state(timer, "is-active"))
        .collect()
}

fn back_up_legacy_units(home: &Path, names: &[&str]) -> Result<()> {
    if names.is_empty() {
        return Ok(());
    }
    let backup_dir = home.join(".config/plasma-addon-manager/backups");
    fs::create_dir_all(&backup_dir)?;
    let backup = tempfile::Builder::new()
        .prefix("migration-")
        .tempdir_in(&backup_dir)?;
    for name in names {
        // Preserve both halves of the old timer/service pair. Old units stay
        // in place; the backup allows manual recovery if the old app is used.
        for unit in [name.to_string(), name.replace(".timer", ".service")] {
            let path = units_dir(home).join(&unit);
            if path.is_file() {
                fs::copy(&path, backup.path().join(unit))?;
            }
        }
    }
    println!("Backed up existing units: {}", backup.keep().display());
    Ok(())
}

fn service_bsdtar_exists(home: &Path) -> bool {
    [
        home.join(".local/bin/bsdtar"),
        PathBuf::from("/usr/bin/bsdtar"),
        PathBuf::from("/usr/local/bin/bsdtar"),
        PathBuf::from("/home/linuxbrew/.linuxbrew/opt/libarchive/bin/bsdtar"),
    ]
    .iter()
    .any(|path| is_executable(path))
}

fn link_bsdtar_for_service(home: &Path, source: &Path) -> Result<()> {
    ensure!(
        is_executable(source),
        "bsdtar at {} is not executable",
        source.display()
    );
    let source = source
        .canonicalize()
        .context("Cannot resolve bsdtar executable")?;
    let target = home.join(".local/bin/bsdtar");
    ensure!(
        fs::symlink_metadata(&target).is_err(),
        "Existing {} cannot be replaced",
        target.display()
    );
    fs::create_dir_all(target.parent().context("Invalid bsdtar destination")?)?;
    symlink(&source, &target)?;
    println!("Made existing bsdtar available to the background service.");
    Ok(())
}

/// Bazzite's working updater GUI provisions libarchive in *user* Homebrew.
/// The GUI asks for consent before calling this; no root or rpm-ostree changes.
pub fn prepare_bazzite_dependencies() -> Result<()> {
    ensure!(
        read_distribution().family == DistributionFamily::AtomicFedora,
        "Homebrew preparation is only for Fedora Atomic / Bazzite"
    );
    ensure!(
        executable_on_path("kpackagetool6").is_some()
            || is_executable(Path::new("/usr/bin/kpackagetool6")),
        "kpackagetool6 is missing from KDE Plasma; cannot replace this OS component with Homebrew"
    );
    let home = home()?;
    if service_bsdtar_exists(&home) {
        println!("✓ bsdtar is already available to the background service.");
        return Ok(());
    }
    if let Some(source) = executable_on_path("bsdtar") {
        link_bsdtar_for_service(&home, &source)?;
        return Ok(());
    }
    let brew = if is_executable(Path::new("/home/linuxbrew/.linuxbrew/bin/brew")) {
        PathBuf::from("/home/linuxbrew/.linuxbrew/bin/brew")
    } else {
        executable_on_path("brew").context("Homebrew is not installed. Install Homebrew or libarchive from Bazzite's graphical software manager")?
    };
    println!("Preparing libarchive for KDE Store updates using user-local Homebrew…");
    output(Command::new(&brew).args(["install", "libarchive"]))?;
    let prefix = output(Command::new(&brew).args(["--prefix", "libarchive"]))?;
    let source = PathBuf::from(String::from_utf8(prefix.stdout)?.trim()).join("bin/bsdtar");
    link_bsdtar_for_service(&home, &source)?;
    ensure!(
        service_bsdtar_exists(&home),
        "bsdtar is still unavailable to the service"
    );
    Ok(())
}

/// Install only the archive utility required by plasmoid-updater. The GUI's
/// existing installer confirmation also authorizes this prerequisite setup.
/// On mutable distributions PolicyKit shows its normal desktop authorization
/// dialog; no password is read from a terminal or passed through the helper.
#[derive(Clone, Debug, PartialEq, Eq)]
struct HostArchivePackage {
    manager: &'static str,
    arguments: &'static [&'static str],
    package: &'static str,
}

fn host_archive_package(family: DistributionFamily) -> Option<HostArchivePackage> {
    match family {
        DistributionFamily::OpenSuse => Some(HostArchivePackage {
            manager: "/usr/bin/zypper",
            arguments: &["--non-interactive", "install", "--no-recommends", "bsdtar"],
            package: "bsdtar",
        }),
        DistributionFamily::Debian => Some(HostArchivePackage {
            manager: "/usr/bin/apt-get",
            arguments: &[
                "install",
                "--yes",
                "--no-install-recommends",
                "libarchive-tools",
            ],
            package: "libarchive-tools",
        }),
        DistributionFamily::Fedora => Some(HostArchivePackage {
            manager: "/usr/bin/dnf",
            arguments: &["install", "--assumeyes", "bsdtar"],
            package: "bsdtar",
        }),
        DistributionFamily::Arch => Some(HostArchivePackage {
            manager: "/usr/bin/pacman",
            arguments: &["--sync", "--needed", "--noconfirm", "libarchive"],
            package: "libarchive",
        }),
        DistributionFamily::AtomicFedora | DistributionFamily::Unknown => None,
    }
}

pub fn ensure_bsdtar_for_install() -> Result<()> {
    let home = home()?;
    if service_bsdtar_exists(&home) {
        println!("✓ bsdtar is already installed; nothing to do.");
        return Ok(());
    }
    if let Some(source) = executable_on_path("bsdtar") {
        link_bsdtar_for_service(&home, &source)?;
        return Ok(());
    }
    let distribution = read_distribution();
    if distribution.family == DistributionFamily::AtomicFedora {
        return prepare_bazzite_dependencies();
    }
    let package = host_archive_package(distribution.family).context(
        "This distribution has no supported bsdtar installer. Install bsdtar from its graphical software manager",
    )?;
    ensure!(
        is_executable(Path::new(package.manager)),
        "Package manager {} is missing; install '{}' using your graphical software manager",
        package.manager,
        package.package
    );
    let pkexec = Path::new("/usr/bin/pkexec");
    ensure!(
        is_executable(pkexec),
        "PolicyKit pkexec is unavailable. Install '{}' using your graphical software manager",
        package.package
    );
    println!(
        "Installing the required '{}' package using {}. Approve the graphical administrator prompt if requested…",
        package.package, package.manager
    );
    io::stdout().flush()?;
    let status = Command::new(pkexec)
        .arg("--disable-internal-agent")
        .arg(package.manager)
        .args(package.arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("Cannot start PolicyKit to install '{}'", package.package))?;
    ensure!(
        status.success(),
        "Installation of '{}' was not completed ({}). Check the administrator authorization and try again",
        package.package,
        status
    );
    ensure!(
        service_bsdtar_exists(&home),
        "Package manager finished, but bsdtar was not found. Check the '{}' package in the software manager",
        package.package
    );
    println!("✓ bsdtar is ready for KDE Store updates and the background agent.");
    Ok(())
}

fn restore_old_timer_states(names: &[(&str, bool, bool)]) {
    for (timer, enabled, active) in names {
        if *enabled {
            let _ = systemctl(&["enable", timer]);
        }
        if *active {
            let _ = systemctl(&["start", timer]);
        }
    }
}

pub fn configure(settings: Settings, migrate_legacy: bool) -> Result<()> {
    settings.validate()?;
    let home = home()?;
    if settings.automatic {
        ensure!(
            find_plasmoid_updater().is_some(),
            "Install plasmoid-updater first using the Install button"
        );
        ensure!(service_bsdtar_exists(&home) || executable_on_path("bsdtar").is_some(),
            "bsdtar is missing. Click Install / check version in Plasma Addon Manager to install the required package as part of updater setup");
    }
    let unit_dir = units_dir(&home);
    let service = unit_dir.join(SERVICE);
    let timer = unit_dir.join(TIMER);
    for target in [&service, &timer] {
        ensure!(
            fs::symlink_metadata(target).is_err() || unit_is_managed(target),
            "Unmanaged unit exists at {}; refusing to overwrite",
            target.display()
        );
    }
    let old_timer_names = legacy_active();
    ensure!(!settings.automatic || old_timer_names.is_empty() || migrate_legacy,
        "Older automatic updater timers are active. Select migration consent in the GUI to disable them safely.");

    let upstream = upstream_config(&home);
    let updated_toml = upstream_document(&upstream, &settings)?;
    let needs_bsdtar_link = settings.automatic && !service_bsdtar_exists(&home);
    let mut targets = vec![
        service.clone(),
        timer.clone(),
        agent_path(&home),
        Settings::path(&home),
        upstream.clone(),
    ];
    if needs_bsdtar_link {
        targets.push(home.join(".local/bin/bsdtar"));
    }
    for target in &targets {
        if let Ok(metadata) = fs::symlink_metadata(target) {
            ensure!(
                !metadata.file_type().is_symlink(),
                "Refusing to replace symlink at {}",
                target.display()
            );
        }
    }
    let saved = snapshot_files(&targets)?;
    let old_self_enabled = user_unit_state(TIMER, "is-enabled");
    let old_self_active = user_unit_state(TIMER, "is-active");
    let old_states: Vec<_> = old_timer_names
        .iter()
        .map(|timer| {
            (
                *timer,
                user_unit_state(timer, "is-enabled"),
                user_unit_state(timer, "is-active"),
            )
        })
        .collect();

    // Every write and systemctl operation after this point is recoverable.
    let apply = (|| -> Result<()> {
        if needs_bsdtar_link {
            let source = executable_on_path("bsdtar").context("Cannot find bsdtar in PATH")?;
            link_bsdtar_for_service(&home, &source)?;
        }
        if settings.automatic {
            install_agent(&home)?;
        }
        if settings.automatic && !old_timer_names.is_empty() && migrate_legacy {
            back_up_legacy_units(&home, &old_timer_names)?;
            for timer in &old_timer_names {
                println!("Disabling the previous timer {timer}…");
                systemctl(&["disable", "--now", timer])?;
            }
        }
        atomic_write(&upstream, updated_toml.to_string().as_bytes())?;
        atomic_write(&service, service_text().as_bytes())?;
        atomic_write(&timer, timer_text(settings.frequency_hours)?.as_bytes())?;
        settings.save(&home)?;
        systemctl(&["daemon-reload"])?;
        if settings.automatic {
            systemctl(&["enable", "--now", TIMER])?;
            println!(
                "✓ Scheduled updates enabled every {} hours.",
                settings.frequency_hours
            );
        } else {
            systemctl(&["disable", "--now", TIMER])?;
            println!("✓ Plasma Addon Manager scheduled updates disabled.");
        }
        Ok(())
    })();
    if let Err(error) = apply {
        eprintln!("Configuration failed. Restoring settings, agent and units…");
        // An enable --now failure can leave a timer enabled, even when its
        // start failed. Disable the partial new unit before restoring files.
        let _ = systemctl(&["disable", "--now", TIMER]);
        restore_files(&saved);
        let _ = systemctl(&["daemon-reload"]);
        if old_self_enabled {
            let _ = systemctl(&["enable", TIMER]);
        }
        if old_self_active {
            let _ = systemctl(&["start", TIMER]);
        }
        restore_old_timer_states(&old_states);
        return Err(error);
    }
    Ok(())
}

pub fn repair_agent() -> Result<()> {
    let home = home()?;
    ensure!(
        unit_is_managed(&units_dir(&home).join(SERVICE))
            && unit_is_managed(&units_dir(&home).join(TIMER)),
        "Agent repair requires units managed by Plasma Addon Manager"
    );
    install_agent(&home)
}

pub fn start_service() -> Result<()> {
    let home = home()?;
    ensure!(
        unit_is_managed(&units_dir(&home).join(SERVICE)),
        "Save automation settings first"
    );
    systemctl(&["start", SERVICE])?;
    println!("Service finished. Open the Journal tab for details.");
    Ok(())
}

pub fn journal() -> Result<()> {
    let result = output(Command::new("journalctl").args([
        "--user",
        "-u",
        SERVICE,
        "-n",
        "100",
        "--no-pager",
    ]))?;
    io::stdout().write_all(&result.stdout)?;
    Ok(())
}

fn transient_failure(output: &Output) -> bool {
    if output.status.success() {
        return false;
    }
    let message = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
    .to_ascii_lowercase();
    [
        "network request failed",
        "timed out",
        "timeout",
        "could not resolve host",
        "temporary failure in name resolution",
        "dns error",
        "connection reset",
        "connection refused",
        "connection closed",
        "502 bad gateway",
        "503 service unavailable",
        "504 gateway timeout",
        "status: 429",
        "status: 502",
        "status: 503",
        "status: 504",
    ]
    .iter()
    .any(|needle| message.contains(needle))
}

fn run_with_retries(
    mut work: impl FnMut() -> Result<Output>,
    mut on_retry: impl FnMut(usize, u64),
    mut wait: impl FnMut(u64),
) -> Result<Output> {
    for (index, delay) in RETRY_DELAYS.iter().copied().enumerate() {
        let result = work()?;
        if !transient_failure(&result) {
            return Ok(result);
        }
        on_retry(index + 2, delay);
        wait(delay);
    }
    work()
}

pub fn run_background() -> Result<Settings> {
    let home = home()?;
    // Require new app-owned settings, never silently adopt legacy GUI configs
    // when running unattended from a systemd service.
    ensure!(
        Settings::path(&home).is_file(),
        "Automation has not been configured"
    );
    let settings = Settings::load(&home)?;
    if !settings.automatic {
        println!("Automatic updates are disabled; skipping.");
        return Ok(settings);
    }
    let _lock = update_lock()?;
    let tool_error = if settings.auto_update_tool {
        println!("Checking updates to the plasmoid-updater tool…");
        let error = updater_installer::install().err();
        if let Some(error) = &error {
            eprintln!("Updater binary check failed (continuing with installed version): {error}");
        }
        error
    } else {
        None
    };
    let binary = find_plasmoid_updater().context("plasmoid-updater is not installed")?;
    let restart = if settings.restart_plasma {
        "--restart-plasma"
    } else {
        "--no-restart-plasma"
    };
    println!(
        "Updating user KDE Store add-ons (restart Plasma: {})…",
        settings.restart_plasma
    );
    let result = run_with_retries(
        || {
            Command::new(&binary)
                .env("PATH", updater_path())
                .args(["--skip-plasma-detection", "update", "--yes", restart])
                .stdin(Stdio::null())
                .output()
                .context("Cannot start plasmoid-updater")
        },
        |attempt, seconds| {
            println!("Temporary KDE Store network error; retry {attempt}/3 in {seconds}s…")
        },
        |seconds| thread::sleep(Duration::from_secs(seconds)),
    )?;
    io::stdout().write_all(&result.stdout)?;
    io::stderr().write_all(&result.stderr)?;
    ensure!(
        result.status.success(),
        "plasmoid-updater failed with status {}",
        result.status
    );
    if let Some(error) = tool_error {
        bail!("Add-ons were updated, but the updater self-update check failed: {error}");
    }
    println!("✓ Automatic update cycle completed.");
    Ok(settings)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::process::ExitStatusExt;

    #[test]
    fn bsdtar_packages_match_supported_distributions() {
        for (family, name, manager) in [
            (DistributionFamily::OpenSuse, "bsdtar", "/usr/bin/zypper"),
            (
                DistributionFamily::Debian,
                "libarchive-tools",
                "/usr/bin/apt-get",
            ),
            (DistributionFamily::Fedora, "bsdtar", "/usr/bin/dnf"),
            (DistributionFamily::Arch, "libarchive", "/usr/bin/pacman"),
        ] {
            let package = host_archive_package(family).unwrap();
            assert_eq!(package.package, name);
            assert_eq!(package.manager, manager);
            assert!(package.arguments.contains(&name));
        }
        assert!(host_archive_package(DistributionFamily::AtomicFedora).is_none());
        assert!(host_archive_package(DistributionFamily::Unknown).is_none());
    }

    #[test]
    fn dashboard_version_ignores_updater_license_text() {
        let output = "plasmoid-updater 0.2.1\nCopyright (c) 2025 uwuclxdy\nLicense GPLv3+\n";
        assert_eq!(
            parse_version(output, "plasmoid-updater ").as_deref(),
            Some("0.2.1")
        );
        assert_eq!(
            parse_version(
                "plasma-addon-manager-agent 0.4.3\n",
                "plasma-addon-manager-agent "
            )
            .as_deref(),
            Some("0.4.3")
        );
        assert_eq!(parse_version("Unknown binary", "plasmoid-updater "), None);
    }
    #[test]
    fn default_is_safe_and_intervals_match_working_guis() {
        let settings = Settings::default();
        assert!(settings.automatic);
        assert!(!settings.restart_plasma);
        assert_eq!(settings.frequency_hours, 24);
        assert_eq!(timer_schedule(6).unwrap(), "*-*-* 00,06,12,18:00:00");
        assert_eq!(timer_schedule(12).unwrap(), "*-*-* 00,12:00:00");
        assert_eq!(timer_schedule(24).unwrap(), "*-*-* 04:00:00");
        assert!(timer_schedule(5).is_err());
    }

    #[test]
    fn settings_round_trip_and_import_legacy() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path();
        let legacy = home.join(".config/bazzite-plasmoid-updater-gui/settings.toml");
        atomic_write(
            &legacy,
            b"automatic = true\nfrequency_hours = 12\nexcluded_packages = [\"weather\"]\n",
        )
        .unwrap();
        let imported = Settings::load(home).unwrap();
        assert_eq!(imported.frequency_hours, 12);
        assert_eq!(imported.excluded_packages, vec!["weather"]);
        imported.save(home).unwrap();
        assert_eq!(Settings::load(home).unwrap(), imported);
    }

    #[test]
    fn refuses_to_modify_unmanaged_units() {
        let dir = tempfile::tempdir().unwrap();
        let path = units_dir(dir.path()).join(TIMER);
        atomic_write(&path, b"[Timer]\nOnCalendar=daily\n").unwrap();
        assert!(!unit_is_managed(&path));
        atomic_write(
            &path,
            format!("[Timer]\n# unrelated\n{MANAGED}\n").as_bytes(),
        )
        .unwrap();
        assert!(!unit_is_managed(&path));
        assert!(!unit_is_managed(&units_dir(dir.path()).join(SERVICE)));
    }

    #[test]
    fn migration_backup_keeps_both_legacy_unit_files() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path();
        atomic_write(
            &units_dir(home).join("plasmoid-updater.timer"),
            b"old timer",
        )
        .unwrap();
        atomic_write(
            &units_dir(home).join("plasmoid-updater.service"),
            b"old service",
        )
        .unwrap();
        back_up_legacy_units(home, &["plasmoid-updater.timer"]).unwrap();
        let backups = home.join(".config/plasma-addon-manager/backups");
        let backup = fs::read_dir(backups)
            .unwrap()
            .next()
            .unwrap()
            .unwrap()
            .path();
        assert_eq!(
            fs::read(backup.join("plasmoid-updater.timer")).unwrap(),
            b"old timer"
        );
        assert_eq!(
            fs::read(backup.join("plasmoid-updater.service")).unwrap(),
            b"old service"
        );
    }

    #[test]
    fn links_existing_bsdtar_into_user_service_path() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path();
        let bin = home.join("custom/bsdtar");
        atomic_write(&bin, b"#!/bin/sh\nexit 0\n").unwrap();
        fs::set_permissions(&bin, fs::Permissions::from_mode(0o755)).unwrap();
        link_bsdtar_for_service(home, &bin).unwrap();
        assert!(service_bsdtar_exists(home));
        assert!(link_bsdtar_for_service(home, &bin).is_err());
    }

    #[test]
    fn preserves_unrelated_upstream_configuration() {
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("plasmoid-updater.toml");
        atomic_write(
            &config,
            b"assume_yes = true\nexcluded_patterns = [\"example\"]\n",
        )
        .unwrap();
        let mut settings = Settings::default();
        settings.excluded_packages.push("clock".into());
        let text = upstream_document(&config, &settings).unwrap().to_string();
        assert!(text.contains("assume_yes = true"));
        assert!(text.contains("excluded_patterns"));
        assert!(text.contains("\"clock\""));
    }

    #[test]
    fn retries_only_transient_network_failures() {
        fn failure(message: &str) -> Output {
            Output {
                status: std::process::ExitStatus::from_raw(2 << 8),
                stdout: vec![],
                stderr: message.as_bytes().to_vec(),
            }
        }
        let mut attempts = 0;
        let mut delays = Vec::new();
        let result = run_with_retries(
            || {
                attempts += 1;
                Ok(if attempts < 3 {
                    failure("network request failed")
                } else {
                    Output {
                        status: std::process::ExitStatus::from_raw(0),
                        stdout: vec![],
                        stderr: vec![],
                    }
                })
            },
            |attempt, delay| delays.push((attempt, delay)),
            |_| {},
        )
        .unwrap();
        assert!(result.status.success());
        assert_eq!(delays, vec![(2, 3), (3, 9)]);
        let mut unexpected = 0;
        run_with_retries(
            || {
                unexpected += 1;
                Ok(failure("permission denied"))
            },
            |_, _| panic!("no retry"),
            |_| panic!("no wait"),
        )
        .unwrap();
        assert_eq!(unexpected, 1);
    }
}
