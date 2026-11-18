//! Read-only system discovery for Plasma Addon Manager.
//! Distribution-specific installation and update operations will be added
//! behind separately tested adapters; the detection layer never installs.

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
    let content = fs::read_to_string("/etc/os-release")
        .or_else(|_| fs::read_to_string("/usr/lib/os-release"))
        .unwrap_or_default();
    detect_distribution(&content)
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
    if let Some(path) = executable_on_path("plasmoid-updater") {
        return Some(path);
    }
    let home = env::var_os("HOME")?;
    let home = PathBuf::from(home);
    [
        home.join(".local/bin/plasmoid-updater"),
        home.join(".cargo/bin/plasmoid-updater"),
    ]
    .into_iter()
    .find(|path| is_executable(path))
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
}
