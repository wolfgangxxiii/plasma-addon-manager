//! System discovery for Plasma Addon Manager.
//! Installation and systemd unit migration remain explicitly out of scope.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DistributionFamily {
    AtomicFedora,
    Debian,
    Fedora,
    Arch,
    OpenSuse,
    Unknown,
}

impl DistributionFamily {
    pub fn label(self) -> &'static str {
        match self {
            Self::AtomicFedora => "Fedora atomic / Bazzite",
            Self::Debian => "Debian / Ubuntu",
            Self::Fedora => "Fedora",
            Self::Arch => "Arch Linux",
            Self::OpenSuse => "openSUSE",
            Self::Unknown => "Unknown (read-only)",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Distribution {
    pub id: String,
    pub pretty_name: String,
    pub family: DistributionFamily,
}

pub fn os_release_value(input: &str, key: &str) -> Option<String> {
    input.lines().find_map(|line| {
        let (name, value) = line.split_once('=')?;
        if name != key {
            return None;
        }
        let value = value.trim();
        let value = value
            .strip_prefix('"')
            .and_then(|part| part.strip_suffix('"'))
            .or_else(|| {
                value
                    .strip_prefix('\'')
                    .and_then(|part| part.strip_suffix('\''))
            })
            .unwrap_or(value);
        Some(value.to_owned())
    })
}

pub fn detect_distribution(input: &str) -> Distribution {
    let id = os_release_value(input, "ID")
        .unwrap_or_else(|| "unknown".into())
        .to_ascii_lowercase();
    let pretty_name = os_release_value(input, "PRETTY_NAME").unwrap_or_else(|| id.clone());
    let like = os_release_value(input, "ID_LIKE").unwrap_or_default();
    let variant = os_release_value(input, "VARIANT_ID").unwrap_or_default();
    let matches = |name: &str| id == name || like.split_whitespace().any(|item| item == name);
    // More specific systems must come before their generic parent family.
    let family = if matches!(id.as_str(), "bazzite" | "ublue" | "silverblue" | "kinoite")
        || id.starts_with("fedora-atomic")
        || (id == "fedora"
            && matches!(
                variant.as_str(),
                "kinoite" | "silverblue" | "sericea" | "onyx"
            )) {
        DistributionFamily::AtomicFedora
    } else if matches("debian") || matches("ubuntu") || matches("neon") {
        DistributionFamily::Debian
    } else if matches("fedora") || matches("rhel") {
        DistributionFamily::Fedora
    } else if matches("arch") || matches("manjaro") || matches("cachyos") {
        DistributionFamily::Arch
    } else if matches("opensuse") || matches("suse") || id.starts_with("opensuse-") {
        DistributionFamily::OpenSuse
    } else {
        DistributionFamily::Unknown
    };

    Distribution {
        id,
        pretty_name,
        family,
    }
}

pub fn read_distribution() -> Distribution {
    // Flatpak's /etc/os-release describes the SDK rather than the host OS.
    let content = fs::read_to_string("/run/host/os-release")
        .or_else(|_| fs::read_to_string("/etc/os-release"))
        .or_else(|_| fs::read_to_string("/usr/lib/os-release"))
        .unwrap_or_default();
    detect_distribution(&content)
}

pub fn in_flatpak() -> bool {
    env::var_os("FLATPAK_ID").is_some() || Path::new("/.flatpak-info").is_file()
}

pub fn is_plasma_session() -> bool {
    if env::var("KDE_FULL_SESSION").as_deref() == Ok("true") {
        return true;
    }
    env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .split([':', ';'])
        .any(|part| part.eq_ignore_ascii_case("KDE"))
}

pub fn executable_on_path(program: &str) -> Option<PathBuf> {
    if program.contains('/') {
        return None;
    }
    env::split_paths(&env::var_os("PATH")?).find_map(|dir| {
        let candidate = dir.join(program);
        is_executable(&candidate).then_some(candidate)
    })
}

#[cfg(unix)]
pub fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path)
        .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
pub fn is_executable(path: &Path) -> bool {
    path.is_file()
}

pub fn find_plasmoid_updater() -> Option<PathBuf> {
    // Match the proven lookup order used by the Bazzite and Debian GUIs:
    // their installs may live outside PATH, especially on atomic desktops.
    let mut candidates = Vec::new();
    if let Some(home) = env::var_os("HOME") {
        let home = PathBuf::from(home);
        candidates.push(home.join(".local/bin/plasmoid-updater"));
        candidates.push(home.join(".cargo/bin/plasmoid-updater"));
    }
    candidates.extend([
        PathBuf::from("/home/linuxbrew/.linuxbrew/bin/plasmoid-updater"),
        PathBuf::from("/usr/local/bin/plasmoid-updater"),
        PathBuf::from("/usr/bin/plasmoid-updater"),
    ]);
    if let Some(paths) = env::var_os("PATH") {
        candidates.extend(env::split_paths(&paths).map(|dir| dir.join("plasmoid-updater")));
    }
    candidates
        .into_iter()
        .find(|path| is_executable(path) && valid_updater_version(path))
}

pub fn valid_updater_version(path: &Path) -> bool {
    let output = std::process::Command::new(path)
        .arg("--version")
        .stdin(std::process::Stdio::null())
        .output();
    output.is_ok_and(|result| {
        result.status.success() && {
            let text = String::from_utf8_lossy(&result.stdout);
            let mut parts = text.split_whitespace();
            parts.next() == Some("plasmoid-updater") && parts.next().is_some()
        }
    })
}

pub fn updater_path() -> String {
    let mut segments = Vec::new();
    if let Some(home) = env::var_os("HOME") {
        segments.push(PathBuf::from(home).join(".local/bin"));
    }
    segments.push(PathBuf::from(
        "/home/linuxbrew/.linuxbrew/opt/libarchive/bin",
    ));
    segments.push(PathBuf::from("/home/linuxbrew/.linuxbrew/bin"));
    if let Some(path) = env::var_os("PATH") {
        segments.extend(env::split_paths(&path));
    } else {
        segments.push(PathBuf::from("/usr/local/bin"));
        segments.push(PathBuf::from("/usr/bin"));
    }
    env::join_paths(segments)
        .unwrap_or_else(|_| std::ffi::OsString::from("/usr/local/bin:/usr/bin"))
        .to_string_lossy()
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_bazzite_before_fedora() {
        let distro = detect_distribution("ID=bazzite\nID_LIKE=\"fedora\"\n");
        assert_eq!(distro.family, DistributionFamily::AtomicFedora);
        let kinoite = detect_distribution("ID=fedora\nVARIANT_ID=kinoite\n");
        assert_eq!(kinoite.family, DistributionFamily::AtomicFedora);
    }

    #[test]
    fn detects_kubuntu_and_neon_as_debian_family() {
        assert_eq!(
            detect_distribution("ID=ubuntu\nID_LIKE=debian\n").family,
            DistributionFamily::Debian
        );
        assert_eq!(
            detect_distribution("ID=neon\nID_LIKE=\"ubuntu debian\"\n").family,
            DistributionFamily::Debian
        );
    }

    #[test]
    fn detects_arch_derivatives() {
        assert_eq!(
            detect_distribution("ID=cachyos\nID_LIKE=arch\n").family,
            DistributionFamily::Arch
        );
        assert_eq!(
            detect_distribution("ID=manjaro\nID_LIKE=arch\n").family,
            DistributionFamily::Arch
        );
    }

    #[test]
    fn detects_opensuse_flavours() {
        assert_eq!(
            detect_distribution("ID=opensuse-tumbleweed\n").family,
            DistributionFamily::OpenSuse
        );
    }

    #[test]
    fn unknown_distro_falls_back_safely() {
        assert_eq!(
            detect_distribution("ID=custom\nPRETTY_NAME=\"My System\"\n"),
            Distribution {
                id: "custom".into(),
                pretty_name: "My System".into(),
                family: DistributionFamily::Unknown
            }
        );
    }

    #[test]
    fn quoted_values_are_unwrapped() {
        assert_eq!(
            os_release_value("PRETTY_NAME=\"openSUSE Tumbleweed\"\n", "PRETTY_NAME"),
            Some("openSUSE Tumbleweed".into())
        );
    }

    #[test]
    fn refuses_paths_as_program_names() {
        assert_eq!(executable_on_path("../../bin/sh"), None);
    }

    #[test]
    fn nonexistent_updater_does_not_pass_validation() {
        assert!(!valid_updater_version(Path::new("/no-such-updater")));
    }
}
