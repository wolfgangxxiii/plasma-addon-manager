//! Explicit allow-list of commands invoked by the Qt frontend.

use plasma_addon_helper::{
    addons,
    automation::{self, Settings},
    executable_on_path, find_plasmoid_updater, in_flatpak, is_plasma_session, read_distribution,
    updater_installer, updater_path, DistributionFamily,
};
use std::env;
use std::io::{self, Write};
use std::process::{Command, Stdio};

// Ported from the working Bazzite and Debian GUIs: never restart the desktop
// on a manual update and never modify the host's system package manager.
const MANUAL_UPDATE_ARGS: &[&str] = &[
    "--skip-plasma-detection",
    "update",
    "--yes",
    "--no-restart-plasma",
];

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    run_command(&mut Command::new(program), args, false)
}

fn run_command(command: &mut Command, args: &[&str], check: bool) -> Result<(), String> {
    let description = format!("{:?}", command.get_program());
    // The child inherits this helper's stdout/stderr, which are already piped
    // to QProcess. Show progress while updates run instead of after they end.
    let status = command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|error| format!("Cannot execute {description}: {error}"))?;
    // `plasmoid-updater check` returns 100 when it finds available updates.
    if status.success() || (check && status.code() == Some(100)) {
        Ok(())
    } else {
        Err(format!("{description} exited with status {status}"))
    }
}

fn run_on_host(program: &str, args: &[&str]) -> Result<(), String> {
    if in_flatpak() {
        // The manifest does not grant host-spawn permissions: users must opt
        // in explicitly. Only allow-listed read-only actions can reach here.
        let mut host_args = vec!["--host", program];
        host_args.extend_from_slice(args);
        run("flatpak-spawn", &host_args).map_err(|error| {
            format!("Host read-only access failed: {error}. An optional Flatpak host bridge requires explicit permission; see README.")
        })
    } else {
        run(program, args)
    }
}

fn diagnose() -> Result<(), String> {
    let distribution = read_distribution();
    println!("Plasma Addon Manager — environment diagnosis");
    println!(
        "Distribution: {} ({})",
        distribution.pretty_name, distribution.id
    );
    println!("Family: {}", distribution.family.label());
    println!("Architecture: {}", env::consts::ARCH);
    println!(
        "KDE Plasma session: {}",
        if is_plasma_session() {
            "detected"
        } else {
            "not detected"
        }
    );
    let mut missing = Vec::new();
    for binary in ["kpackagetool6", "curl", "bsdtar", "systemctl", "journalctl"] {
        let executable = executable_on_path(binary);
        if executable.is_none() && binary != "journalctl" {
            missing.push(binary);
        }
        println!(
            "{}: {}",
            binary,
            executable
                .map(|path| path.display().to_string())
                .unwrap_or_else(|| "missing".into())
        );
    }
    println!(
        "plasmoid-updater: {}",
        if in_flatpak() {
            "host CLI (optional flatpak-spawn bridge)".into()
        } else {
            find_plasmoid_updater()
                .map(|path| path.display().to_string())
                .unwrap_or_else(|| "not installed".into())
        }
    );
    if in_flatpak() {
        println!("Flatpak: host command access is disabled by default; explicit opt-in required");
    }
    println!("Mode: verified installer, manual updates and systemd --user automation");
    if missing.is_empty() {
        Ok(())
    } else {
        let hint = if distribution.family == DistributionFamily::OpenSuse
            && missing.contains(&"bsdtar")
        {
            "On openSUSE install the 'bsdtar' package in YaST Software Management or Discover."
        } else {
            "Install the missing dependencies using your distribution's software manager."
        };
        Err(format!("Missing required dependencies: {}. {hint}", missing.join(", ")))
    }
}

fn updater(action: &str) -> Result<(), String> {
    if in_flatpak() {
        return Err("Updating host add-ons is available only from the AppImage or native application, not a Flatpak sandbox".into());
    }
    let binary = find_plasmoid_updater().ok_or(
        "No working plasmoid-updater found. Choose Install / check version in the dashboard first.",
    )?;
    let mut command = Command::new(binary);
    command.env("PATH", updater_path());
    match action {
        "inventory" => run_command(
            &mut command,
            &["--skip-plasma-detection", "list-installed"],
            false,
        ),
        "check" => run_command(&mut command, &["--skip-plasma-detection", "check"], true),
        "dry-run" => {
            let help = command
                .args(["--skip-plasma-detection", "update", "--help"])
                .stdin(Stdio::null())
                .output()
                .map_err(|error| format!("Cannot inspect updater options: {error}"))?;
            if !help.status.success() {
                return Err(
                    "Cannot inspect updater options safely; no update was performed".into(),
                );
            }
            let supports_dry_run = String::from_utf8_lossy(&help.stdout).contains("--dry-run");
            // Reset arguments in a new command because Command::args appends.
            let mut update = Command::new(command.get_program());
            update.env("PATH", updater_path());
            if supports_dry_run {
                println!("Preview: plasmoid-updater update --dry-run");
                run_command(
                    &mut update,
                    &["--skip-plasma-detection", "update", "--dry-run"],
                    false,
                )
            } else {
                println!("This version has no --dry-run; using the read-only check command.");
                run_command(&mut update, &["--skip-plasma-detection", "check"], true)
            }
        }
        "update" => {
            let _lock = automation::update_lock().map_err(|error| format!("{error:#}"))?;
            println!("Applying KDE Store add-on updates; Plasma will not restart automatically.");
            io::stdout().flush().map_err(|error| error.to_string())?;
            run_command(&mut command, MANUAL_UPDATE_ARGS, false)
        }
        _ => Err(format!("Unknown updater action: {action}")),
    }
}

fn execute(action: &str, extra: &[String]) -> Result<(), String> {
    match action {
        "diagnose" => diagnose(),
        "inventory" | "check" => {
            let command = if action == "inventory" {
                "list-installed"
            } else {
                "check"
            };
            if in_flatpak() {
                run_on_host("plasmoid-updater", &[command])
            } else {
                updater(action)
            }
        }
        "dry-run" | "update" => updater(action),
        "install" => {
            if in_flatpak() {
                Err("Install from the standalone AppImage, not a Flatpak sandbox".into())
            } else {
                updater_installer::install()?;
                if read_distribution().family == DistributionFamily::AtomicFedora {
                    automation::prepare_bazzite_dependencies()
                        .map_err(|error| format!("Bazzite prerequisites: {error:#}"))?;
                } else if executable_on_path("bsdtar").is_none() {
                    println!("The updater binary is installed, but KDE Store updates require bsdtar.");
                    if read_distribution().family == DistributionFamily::OpenSuse {
                        println!("On openSUSE install the 'bsdtar' package in YaST or Discover.");
                    } else {
                        println!("Install the libarchive/bsdtar utility with your software manager.");
                    }
                }
                Ok(())
            }
        }
        "settings-show" => {
            let settings = Settings::load(&automation::home().map_err(|error| error.to_string())?)
                .map_err(|error| error.to_string())?;
            println!(
                "{}",
                serde_json::to_string(&settings).map_err(|error| error.to_string())?
            );
            Ok(())
        }
        "status-json" => {
            let data = automation::dashboard_state().map_err(|error| format!("{error:#}"))?;
            println!(
                "{}",
                serde_json::to_string(&data).map_err(|error| error.to_string())?
            );
            Ok(())
        }
        "inventory-json" => {
            let data = addons::inventory().map_err(|error| format!("{error:#}"))?;
            println!(
                "{}",
                serde_json::to_string(&data).map_err(|error| error.to_string())?
            );
            Ok(())
        }
        "updates-json" => {
            let data = addons::updates().map_err(|error| format!("{error:#}"))?;
            println!(
                "{}",
                serde_json::to_string(&data).map_err(|error| error.to_string())?
            );
            Ok(())
        }
        "settings-save" => {
            if in_flatpak() {
                return Err("Automation changes require the AppImage, not Flatpak".into());
            }
            if extra.len() != 2 {
                return Err("Expected settings JSON and migration choice".into());
            }
            let settings: Settings = serde_json::from_str(&extra[0])
                .map_err(|error| format!("Invalid settings: {error}"))?;
            let takeover = match extra[1].as_str() {
                "migrate" => true,
                "keep" => false,
                _ => return Err("Unknown migration choice".into()),
            };
            automation::configure(settings, takeover).map_err(|error| format!("{error:#}"))
        }
        "timer" => {
            automation::status();
            Ok(())
        }
        "test-config" => automation::test_configuration().map_err(|error| format!("{error:#}")),
        "journal" => automation::journal().map_err(|error| format!("{error:#}")),
        "repair-agent" => automation::repair_agent().map_err(|error| format!("{error:#}")),
        "run-service" => automation::start_service().map_err(|error| format!("{error:#}")),
        "--help" | "help" => {
            println!("Usage: plasma-addon-helper [diagnose|inventory|check|inventory-json|updates-json|status-json|dry-run|update|install|settings-show|settings-save|test-config|timer|journal|repair-agent|run-service]");
            println!("Modifying actions require explicit GUI confirmation. Only user-owned KDE add-ons and systemd --user settings are touched; the OS image is never changed.");
            Ok(())
        }
        _ => Err(format!("Unknown action '{action}'. Use --help.")),
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let action = args.first().map(String::as_str).unwrap_or("diagnose");
    if let Err(error) = execute(action, args.get(1..).unwrap_or(&[])) {
        eprintln!("Error: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manual_update_is_explicit_and_never_restarts_plasma() {
        assert!(MANUAL_UPDATE_ARGS.contains(&"--yes"));
        assert!(MANUAL_UPDATE_ARGS.contains(&"--no-restart-plasma"));
        assert!(!MANUAL_UPDATE_ARGS.contains(&"--restart-plasma"));
    }
}
