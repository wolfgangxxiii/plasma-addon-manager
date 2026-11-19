//! Verified, user-local installer adapted from the author's working Bazzite
//! and Debian updater GUIs. It never touches the OS image or systemd units.

use crate::find_plasmoid_updater;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const UPSTREAM: &str = "https://github.com/uwuclxdy/plasmoid-updater";
const RELEASE_API: &str = "https://api.github.com/repos/uwuclxdy/plasmoid-updater/releases/latest";

#[derive(Debug, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
    digest: Option<String>,
}

fn progress(message: &str) {
    println!("{message}");
    let _ = io::stdout().flush();
}

fn download(url: &str, destination: &Path) -> Result<(), String> {
    let output = Command::new("curl")
        .args([
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--retry",
            "2",
            "--connect-timeout",
            "15",
            "--max-time",
            "180",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--user-agent",
            "PlasmaAddonManager/0.3.0",
            "--output",
        ])
        .arg(destination)
        .arg(url)
        .stdin(Stdio::null())
        .output()
        .map_err(|error| format!("Cannot start curl: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(format!(
            "Download failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ))
    }
}

fn verified_asset(release: &GitHubRelease) -> Result<(&str, &str), String> {
    let asset = release
        .assets
        .iter()
        .find(|item| {
            matches!(
                item.name.as_str(),
                "plasmoid-updater-linux-x64" | "plasmoid-updater-linux-x86_64"
            )
        })
        .ok_or("GitHub release has no supported Linux x86_64 binary")?;
    if !asset
        .browser_download_url
        .starts_with(&format!("{UPSTREAM}/releases/download/"))
    {
        return Err("Unexpected updater download URL".into());
    }
    let digest = asset
        .digest
        .as_deref()
        .ok_or("GitHub release has no SHA-256 digest; refusing to install")?;
    let checksum = digest
        .strip_prefix("sha256:")
        .ok_or("Unsupported checksum type; refusing to install")?;
    if checksum.len() != 64 || !checksum.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("Invalid SHA-256 digest; refusing to install".into());
    }
    Ok((&asset.browser_download_url, checksum))
}

fn verify_checksum(path: &Path, expected: &str) -> Result<(), String> {
    let mut file = File::open(path).map_err(|error| error.to_string())?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 16 * 1024];
    loop {
        let count = file.read(&mut buffer).map_err(|error| error.to_string())?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    if !format!("{:x}", hasher.finalize()).eq_ignore_ascii_case(expected) {
        return Err("Downloaded binary SHA-256 mismatch; installation cancelled".into());
    }
    Ok(())
}

fn version_of(path: &Path) -> Option<String> {
    let output = Command::new(path)
        .arg("--version")
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let mut parts = text.split_whitespace();
    (parts.next() == Some("plasmoid-updater"))
        .then(|| parts.next().map(str::to_owned))
        .flatten()
}

fn parse_version(text: &str) -> Option<Vec<u32>> {
    text.split('.')
        .map(str::parse::<u32>)
        .collect::<Result<Vec<_>, _>>()
        .ok()
        .filter(|parts| parts.len() == 3)
}

fn already_current(installed: Option<&str>, release: &str) -> bool {
    installed.is_some_and(|version| {
        let latest = release.trim_start_matches('v');
        version == latest
            || parse_version(version)
                .zip(parse_version(latest))
                .is_some_and(|(current, latest)| current >= latest)
    })
}

fn stage_and_install(binary: &Path, target: &Path) -> Result<(), String> {
    let parent = target.parent().ok_or("Invalid install path")?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let mut staged = tempfile::NamedTempFile::new_in(parent).map_err(|error| error.to_string())?;
    io::copy(
        &mut File::open(binary).map_err(|error| error.to_string())?,
        &mut staged,
    )
    .map_err(|error| error.to_string())?;
    staged
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o755))
        .map_err(|error| error.to_string())?;
    // Close the write handle before running --version (Linux rejects ETXTBSY).
    let staged = staged.into_temp_path();
    version_of(staged.as_ref())
        .ok_or("Downloaded binary failed --version; existing install preserved")?;
    staged.persist(target).map_err(|error| error.to_string())?;
    Ok(())
}

pub fn install() -> Result<(), String> {
    if env::consts::ARCH != "x86_64" {
        return Err("The upstream updater installer currently supports x86_64 only".into());
    }
    let home = env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or("HOME is unavailable; cannot install into user account")?;
    let temporary = tempfile::tempdir().map_err(|error| error.to_string())?;
    let metadata = temporary.path().join("release.json");
    let binary = temporary.path().join("plasmoid-updater-linux-x86_64");
    progress("Reading the latest plasmoid-updater release from GitHub…");
    download(RELEASE_API, &metadata)?;
    let release: GitHubRelease =
        serde_json::from_slice(&fs::read(&metadata).map_err(|error| error.to_string())?)
            .map_err(|error| format!("Invalid GitHub release metadata: {error}"))?;

    let existing = find_plasmoid_updater();
    let installed_version = existing.as_deref().and_then(version_of);
    if already_current(installed_version.as_deref(), &release.tag_name) {
        progress(&format!(
            "A current plasmoid-updater ({}) is already installed; leaving it untouched.",
            installed_version.unwrap_or_default()
        ));
        return Ok(());
    }

    let (url, checksum) = verified_asset(&release)?;
    progress(&format!(
        "Downloading verified updater {}…",
        release.tag_name
    ));
    download(url, &binary)?;
    verify_checksum(&binary, checksum)?;
    progress("SHA-256 verified. Installing into ~/.local/bin…");
    stage_and_install(&binary, &home.join(".local/bin/plasmoid-updater"))?;
    progress("Installation complete. No system image or systemd settings were changed.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn release_must_have_trusted_url_and_sha256() {
        let release = GitHubRelease {
            tag_name: "v0.2.1".into(),
            assets: vec![GitHubAsset {
                name: "plasmoid-updater-linux-x64".into(),
                browser_download_url: format!(
                    "{UPSTREAM}/releases/download/v0.2.1/plasmoid-updater-linux-x64"
                ),
                digest: Some(format!("sha256:{}", "a".repeat(64))),
            }],
        };
        assert!(verified_asset(&release).is_ok());
        let mut bad = release;
        bad.assets[0].browser_download_url = "https://example.org/binary".into();
        assert!(verified_asset(&bad).is_err());
        bad.assets[0].browser_download_url = format!("{UPSTREAM}/releases/download/v0.2.1/a");
        bad.assets[0].digest = None;
        assert!(verified_asset(&bad).is_err());
    }

    #[test]
    fn never_downgrade_or_replace_current_install() {
        assert!(already_current(Some("0.2.1"), "v0.2.1"));
        assert!(already_current(Some("0.2.2"), "v0.2.1"));
        assert!(!already_current(Some("0.2.0"), "v0.2.1"));
    }

    #[test]
    fn reject_tampered_binary() {
        let file = tempfile::NamedTempFile::new().unwrap();
        fs::write(file.path(), b"tampered").unwrap();
        assert!(verify_checksum(file.path(), &"0".repeat(64)).is_err());
    }
}
