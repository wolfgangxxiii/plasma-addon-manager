//! Explicit allow-list of commands invoked by the Qt frontend.

use plasma_addon_helper::{
    executable_on_path, find_plasmoid_updater, in_flatpak, is_plasma_session, read_distribution,
    updater_path,
};
use std::env;
use std::io::{self, Write};
use std::process::{Command, Stdio};

// Ported from the working Bazzite and Debian GUIs: never restart the desktop
// on a manual update and never modify the host's system package manager.
const MANUAL_UPDATE_ARGS: &[&str] = &[
    "--skip-plasma-detection", "update", "--yes", "--no-restart-plasma",
];

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    run_command(&mut Command::new(program), args, false)
}

fn run_command(command: &mut Command, args: &[&str], check: bool) -> Result<(), String> {
    let description = format!("{:?}", command.get_program());
    let output = command.args(args).stdin(Stdio::null()).output()
        .map_err(|error| format!("Cannot execute {description}: {error}"))?;
    io::stdout()
        .write_all(&output.stdout)
        .map_err(|error| error.to_string())?;
    io::stderr()
        .write_all(&output.stderr)
        .map_err(|error| error.to_string())?;
    // `plasmoid-updater check` returns 100 when it finds available updates.
    if output.status.success() || (check && output.status.code() == Some(100)) {
        Ok(())
    } else {
        Err(format!("{description} exited with status {}", output.status))
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

fn diagnose() {
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
    for binary in ["kpackagetool6", "curl", "bsdtar", "systemctl", "journalctl"] {
        println!(
            "{}: {}",
            binary,
            executable_on_path(binary)
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
    println!("Mode: inspection + confirmed manual updates; no installer or scheduler migration");
}

fn updater(action: &str) -> Result<(), String> {
    if in_flatpak() {
        return Err("Updating host add-ons is available only from the AppImage or native application, not a Flatpak sandbox".into());
    }
    let binary = find_plasmoid_updater()
        .ok_or("No working plasmoid-updater found. Install it using your existing Bazzite/Debian updater GUI first.")?;
    let mut command = Command::new(binary);
    command.env("PATH", updater_path());
    match action {
        "inventory" => run_command(&mut command, &["--skip-plasma-detection", "list-installed"], false),
        "check" => run_command(&mut command, &["--skip-plasma-detection", "check"], true),
        "dry-run" => {
            let help = command.args(["--skip-plasma-detection", "update", "--help"])
                .stdin(Stdio::null()).output()
                .map_err(|error| format!("Cannot inspect updater options: {error}"))?;
            if !help.status.success() {
                return Err("Cannot inspect updater options safely; no update was performed".into());
            }
            let supports_dry_run = String::from_utf8_lossy(&help.stdout).contains("--dry-run");
            // Reset arguments in a new command because Command::args appends.
            let mut update = Command::new(command.get_program());
            update.env("PATH", updater_path());
            if supports_dry_run {
                println!("Preview: plasmoid-updater update --dry-run");
                run_command(&mut update, &["--skip-plasma-detection", "update", "--dry-run"], false)
            } else {
                println!("This version has no --dry-run; using the read-only check command.");
                run_command(&mut update, &["--skip-plasma-detection", "check"], true)
            }
        }
        "update" => {
            println!("Applying KDE Store add-on updates; Plasma will not restart automatically.");
            io::stdout().flush().map_err(|error| error.to_string())?;
            run_command(&mut command, MANUAL_UPDATE_ARGS, false)
        }
        _ => Err(format!("Unknown updater action: {action}")),
    }
}

fn execute(action: &str) -> Result<(), String> {
    match action {
        "diagnose" => {
            diagnose();
            Ok(())
        }
        "inventory" | "check" => {
            let command = if action == "inventory" { "list-installed" } else { "check" };
            if in_flatpak() {
                run_on_host("plasmoid-updater", &[command])
            } else {
                updater(action)
            }
        }
        "dry-run" | "update" => updater(action),
        "timer" => run_on_host(
            "systemctl",
            &["--user", "status", "plasmoid-updater.timer", "--no-pager"],
        ),
        "journal" => run_on_host(
            "journalctl",
            &[
                "--user",
                "-u",
                "plasmoid-updater.service",
                "-n",
                "80",
                "--no-pager",
            ],
        ),
        "--help" | "help" => {
            println!("Usage: plasma-addon-helper [diagnose|inventory|check|dry-run|update|timer|journal]");
            println!("Only 'update' modifies user add-ons; GUI requires confirmation. No system packages or services are changed.");
            Ok(())
        }
        _ => Err(format!("Unknown action '{action}'. Use --help.")),
    }
}

fn main() {
    let action = env::args().nth(1).unwrap_or_else(|| "diagnose".into());
    if let Err(error) = execute(&action) {
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
