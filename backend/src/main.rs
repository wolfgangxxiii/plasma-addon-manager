//! Strict allow-list of non-mutating commands invoked by the Qt frontend.

use plasma_addon_helper::{
    executable_on_path, find_plasmoid_updater, in_flatpak, is_plasma_session, read_distribution,
};
use std::env;
use std::io::{self, Write};
use std::process::{Command, Stdio};

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let output = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .map_err(|error| format!("Cannot execute {program}: {error}"))?;
    io::stdout()
        .write_all(&output.stdout)
        .map_err(|error| error.to_string())?;
    io::stderr()
        .write_all(&output.stderr)
        .map_err(|error| error.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        Err(format!("{program} exited with status {}", output.status))
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
    println!("Mode: read-only foundation; installation is not enabled yet");
}

fn execute(action: &str) -> Result<(), String> {
    match action {
        "diagnose" => {
            diagnose();
            Ok(())
        }
        "inventory" | "check" => {
            let command = if action == "inventory" {
                "list-installed"
            } else {
                "check"
            };
            if in_flatpak() {
                run_on_host("plasmoid-updater", &[command])
            } else {
                let updater = find_plasmoid_updater().ok_or(
                    "plasmoid-updater not found. Installation is coming in a later milestone.",
                )?;
                run(&updater.to_string_lossy(), &[command])
            }
        }
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
            println!("Usage: plasma-addon-helper [diagnose|inventory|check|timer|journal]");
            println!("All operations are read-only; this version never installs or updates.");
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
