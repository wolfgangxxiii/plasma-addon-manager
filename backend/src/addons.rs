//! Structured KDE Store add-on data adapted from the working Bazzite and
//! Debian GUIs. Handle both the published plasmoid-updater 0.2.1 text tables
//! and the forthcoming upstream JSON output without changing installed add-ons.

use crate::{find_plasmoid_updater, updater_path};
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::Duration;

const RETRY_DELAYS: &[u64] = &[3, 9];
const COMPONENT_TYPES: &[&str] = &[
    "Aurorae Decoration",
    "Wallpaper Plugin",
    "Plasma Widget",
    "KWin Switcher",
    "KWin Effect",
    "KWin Script",
    "Global Theme",
    "Plasma Style",
    "Color Scheme",
    "Splash Screen",
    "SDDM Theme",
    "Icon Theme",
    "Wallpaper",
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct InstalledAddon {
    pub name: String,
    pub directory_name: String,
    pub version: String,
    pub component_type: String,
    pub path: String,
    pub is_system: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AvailableAddonUpdate {
    pub installed: InstalledAddon,
    pub latest_version: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct AddonIssue {
    pub name: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct UpdateOverview {
    pub available: Vec<AvailableAddonUpdate>,
    pub issues: Vec<AddonIssue>,
    pub skipped: usize,
    pub unmatched: usize,
}

#[derive(Debug, Deserialize)]
struct InstalledResponse {
    components: Vec<InstalledAddon>,
}

#[derive(Debug, Deserialize)]
struct UpdateResponse {
    available_updates: Vec<AvailableAddonUpdate>,
    #[serde(default)]
    diagnostics: Vec<serde_json::Value>,
    #[serde(default)]
    unavailable: Vec<serde_json::Value>,
    #[serde(default)]
    skipped: Vec<serde_json::Value>,
    #[serde(default)]
    unmatched: Vec<serde_json::Value>,
}

fn network_error(result: &Output) -> bool {
    if result.status.success() {
        return false;
    }
    let message = format!(
        "{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
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
    mut command: impl FnMut() -> Result<Output>,
    mut wait: impl FnMut(u64),
) -> Result<Output> {
    for delay in RETRY_DELAYS {
        let result = command()?;
        if !network_error(&result) {
            return Ok(result);
        }
        wait(*delay);
    }
    command()
}

fn checked_output(binary: &std::path::Path, args: &[&str], accepted: &[i32]) -> Result<Vec<u8>> {
    let result = run_with_retries(
        || {
            Command::new(binary)
                .args(["--skip-plasma-detection"])
                .args(args)
                .env("PATH", updater_path())
                .env("NO_COLOR", "1")
                .env("CLICOLOR", "0")
                .stdin(Stdio::null())
                .output()
                .context("Cannot start plasmoid-updater")
        },
        |seconds| thread::sleep(Duration::from_secs(seconds)),
    )?;
    if !result.status.success()
        && !result
            .status
            .code()
            .is_some_and(|code| accepted.contains(&code))
    {
        bail!(
            "plasmoid-updater exited with {}: {}",
            result.status,
            String::from_utf8_lossy(&result.stderr).trim()
        );
    }
    Ok(result.stdout)
}

fn unsupported_json(error: &anyhow::Error) -> bool {
    let message = format!("{error:#}");
    message.contains("exit status: 2") && message.contains("unexpected argument '--json'")
}

fn legacy_fields(line: &str) -> Option<(Vec<&str>, &str)> {
    COMPONENT_TYPES.iter().find_map(|kind| {
        let prefix = line.trim().strip_suffix(*kind)?;
        if !prefix.chars().last().is_some_and(char::is_whitespace) {
            return None;
        }
        Some((prefix.split_whitespace().collect(), *kind))
    })
}

fn legacy_rows<'a>(input: &'a str, headers: &[&str], empty: &str) -> Result<Vec<&'a str>> {
    if input.trim().eq_ignore_ascii_case(empty) {
        return Ok(Vec::new());
    }
    let mut lines = input.lines();
    ensure_header(&mut lines, headers, input)?;
    Ok(lines.filter(|line| !line.trim().is_empty()).collect())
}

fn ensure_header<'a>(
    lines: &mut impl Iterator<Item = &'a str>,
    headers: &[&str],
    text: &str,
) -> Result<()> {
    if !lines.any(|line| line.split_whitespace().eq(headers.iter().copied())) {
        bail!("Unexpected plasmoid-updater table: {text}");
    }
    Ok(())
}

fn parse_legacy_installed(input: &[u8], is_system: bool) -> Result<Vec<InstalledAddon>> {
    let text = std::str::from_utf8(input).context("Invalid add-on list encoding")?;
    legacy_rows(
        text,
        &["NAME", "VERSION", "TYPE"],
        "no components installed",
    )?
    .into_iter()
    .map(|row| {
        let (mut fields, kind) =
            legacy_fields(row).ok_or_else(|| anyhow!("Invalid add-on row: {row}"))?;
        let version = fields.pop().context("Missing installed version")?;
        anyhow::ensure!(!fields.is_empty(), "Missing add-on name");
        let name = fields.join(" ");
        Ok(InstalledAddon {
            directory_name: name.clone(),
            name,
            version: version.to_owned(),
            component_type: kind.to_owned(),
            path: String::new(),
            is_system,
        })
    })
    .collect()
}

fn parse_legacy_updates(input: &[u8]) -> Result<UpdateOverview> {
    let text = std::str::from_utf8(input).context("Invalid update list encoding")?;
    let available = legacy_rows(
        text,
        &["NAME", "CURRENT", "AVAILABLE", "ID", "SIZE", "TYPE"],
        "no updates available",
    )?
    .into_iter()
    .map(|row| {
        let (mut fields, kind) =
            legacy_fields(row).ok_or_else(|| anyhow!("Invalid update row: {row}"))?;
        let size = fields.pop().context("Missing size")?;
        if matches!(
            size,
            "B" | "KB" | "MB" | "GB" | "TB" | "KiB" | "MiB" | "GiB" | "TiB"
        ) {
            fields.pop().context("Missing numeric size")?;
        }
        let id = fields.pop().context("Missing KDE Store ID")?;
        anyhow::ensure!(id.parse::<u64>().is_ok(), "Invalid KDE Store ID: {id}");
        let latest_version = fields
            .pop()
            .context("Missing available version")?
            .to_owned();
        let version = fields
            .pop()
            .context("Missing installed version")?
            .to_owned();
        anyhow::ensure!(!fields.is_empty(), "Missing add-on name");
        let name = fields.join(" ");
        Ok(AvailableAddonUpdate {
            installed: InstalledAddon {
                directory_name: name.clone(),
                name,
                version,
                component_type: kind.to_owned(),
                path: String::new(),
                is_system: false,
            },
            latest_version,
        })
    })
    .collect::<Result<Vec<_>>>()?;
    Ok(UpdateOverview {
        available,
        issues: Vec::new(),
        skipped: 0,
        unmatched: 0,
    })
}

fn inventory_in(binary: &std::path::Path, system: bool) -> Result<Vec<InstalledAddon>> {
    let args: &[&str] = if system {
        &["--system", "list-installed", "--json"]
    } else {
        &["list-installed", "--json"]
    };
    let mut addons = match checked_output(binary, args, &[]) {
        Ok(bytes) => {
            serde_json::from_slice::<InstalledResponse>(&bytes)
                .context("Invalid inventory JSON")?
                .components
        }
        Err(error) if unsupported_json(&error) => {
            let legacy_args: &[&str] = if system {
                &["--system", "list-installed"]
            } else {
                &["list-installed"]
            };
            parse_legacy_installed(&checked_output(binary, legacy_args, &[])?, system)?
        }
        Err(error) => return Err(error),
    };
    addons.sort_by_key(|item| item.name.to_lowercase());
    Ok(addons)
}

pub fn inventory() -> Result<Vec<InstalledAddon>> {
    let binary = find_plasmoid_updater().context("Install plasmoid-updater first")?;
    let mut addons = inventory_in(&binary, false)?;
    // System-installed entries are optional, read-only information. Missing
    // permissions or support must not hide the user's own installed add-ons.
    match inventory_in(&binary, true) {
        Ok(mut system) => addons.append(&mut system),
        Err(error) => eprintln!("System add-ons could not be listed: {error:#}"),
    }
    Ok(addons)
}

fn updates_in(binary: &std::path::Path) -> Result<UpdateOverview> {
    let bytes = match checked_output(binary, &["check", "--json"], &[1, 100]) {
        Ok(bytes) => bytes,
        Err(error) if unsupported_json(&error) => {
            return parse_legacy_updates(&checked_output(binary, &["check"], &[1, 100])?)
        }
        Err(error) => return Err(error),
    };
    let parsed: UpdateResponse = serde_json::from_slice(&bytes).context("Invalid update JSON")?;
    let issues = parsed
        .diagnostics
        .into_iter()
        .chain(parsed.unavailable)
        .map(|item| AddonIssue {
            name: item
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("Unknown add-on")
                .to_owned(),
            reason: item
                .get("reason")
                .and_then(|v| v.as_str())
                .unwrap_or("Unable to check update")
                .to_owned(),
        })
        .collect();
    Ok(UpdateOverview {
        available: parsed.available_updates,
        issues,
        skipped: parsed.skipped.len(),
        unmatched: parsed.unmatched.len(),
    })
}

pub fn updates() -> Result<UpdateOverview> {
    let binary = find_plasmoid_updater().context("Install plasmoid-updater first")?;
    updates_in(&binary)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::process::ExitStatusExt;

    #[test]
    fn legacy_tables_with_multiword_addon_names() {
        let installed =
            parse_legacy_installed(b"NAME VERSION TYPE\nWindow List 1.3 Plasma Widget\n", false)
                .unwrap();
        assert_eq!(installed[0].name, "Window List");
        assert_eq!(installed[0].component_type, "Plasma Widget");
        let updates = parse_legacy_updates(
            b"NAME CURRENT AVAILABLE ID SIZE TYPE\nWindow List 1.3 1.4 1234 12 KB Plasma Widget\n",
        )
        .unwrap();
        assert_eq!(updates.available[0].latest_version, "1.4");
        assert_eq!(updates.available[0].installed.name, "Window List");
    }

    #[test]
    fn no_updates_and_malformed_tables() {
        assert!(parse_legacy_updates(b"No updates available")
            .unwrap()
            .available
            .is_empty());
        assert!(parse_legacy_installed(b"BAD HEADER", false).is_err());
        assert!(
            parse_legacy_updates(b"NAME CURRENT AVAILABLE ID SIZE TYPE\nMissing everything\n")
                .is_err()
        );
    }

    #[test]
    fn parses_new_updater_json() {
        let data = br#"{"components":[{"name":"Weather","directory_name":"weather","version":"1.0","component_type":"Plasma Widget","path":"/home/u/weather","is_system":false}]}"#;
        let parsed: InstalledResponse = serde_json::from_slice(data).unwrap();
        assert_eq!(parsed.components.len(), 1);
        let data = br#"{"available_updates":[],"diagnostics":[{"name":"Clock","reason":"KDE Store unavailable"}],"skipped":[],"unmatched":[]}"#;
        let parsed: UpdateResponse = serde_json::from_slice(data).unwrap();
        assert_eq!(parsed.diagnostics.len(), 1);
    }

    #[test]
    fn transient_failure_does_not_retry_permission_errors() {
        fn failure(text: &str) -> Output {
            Output {
                status: std::process::ExitStatus::from_raw(2 << 8),
                stdout: vec![],
                stderr: text.as_bytes().to_vec(),
            }
        }
        let mut attempts = 0;
        run_with_retries(
            || {
                attempts += 1;
                Ok(failure("permission denied"))
            },
            |_| panic!("unexpected retry"),
        )
        .unwrap();
        assert_eq!(attempts, 1);
    }

    #[test]
    fn published_updater_falls_back_from_json_to_text_tables() {
        let dir = tempfile::tempdir().unwrap();
        let binary = dir.path().join("plasmoid-updater");
        std::fs::write(
            &binary,
            b"#!/bin/sh\ncase \"$*\" in\n  *--json*) echo \"error: unexpected argument '--json' found\" >&2; exit 2;;\n  *list-installed*) printf 'NAME VERSION TYPE\\nWindow List 1.3 Plasma Widget\\n';;\n  *check*) printf 'NAME CURRENT AVAILABLE ID SIZE TYPE\\nWindow List 1.3 1.4 1234 12 KB Plasma Widget\\n'; exit 100;;\nesac\n",
        )
        .unwrap();
        std::fs::set_permissions(&binary, std::fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(inventory_in(&binary, false).unwrap()[0].name, "Window List");
        assert!(inventory_in(&binary, true).unwrap()[0].is_system);
        assert_eq!(
            updates_in(&binary).unwrap().available[0].latest_version,
            "1.4"
        );
    }
}
