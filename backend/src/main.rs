//! Strict allow-list of non-mutating commands invoked by the Qt frontend.

use plasma_addon_helper::{
    executable_on_path, find_plasmoid_updater, is_plasma_session, read_distribution,
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
        find_plasmoid_updater()
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| "not installed".into())
    );
    println!("Mode: read-only foundation; installation is not enabled yet");
}

fn execute(action: &str) -> Result<(), String> {
    match action {
        "diagnose" => {
            diagnose();
            Ok(())
        }
        "inventory" | "check" => {
            let updater = find_plasmoid_updater().ok_or(
                "plasmoid-updater not found. Installation is coming in a later milestone.",
            )?;
            let command = if action == "inventory" {
                "list-installed"
            } else {
                "check"
            };
            run(&updater.to_string_lossy(), &[command])
        }
        "timer" => run(
            "systemctl",
            &["--user", "status", "plasmoid-updater.timer", "--no-pager"],
        ),
        "journal" => run(
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
