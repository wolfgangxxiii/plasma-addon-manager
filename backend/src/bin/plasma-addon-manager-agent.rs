//! Headless systemd --user companion, independently installed from AppImage.
//! Adapted from the proven Bazzite and Debian plasmoid-updater agents.

use plasma_addon_helper::automation::{self, Settings};
use std::process::{Command, ExitCode, Stdio};

fn notify(summary: &str, message: &str) {
    let _ = Command::new("notify-send")
        .args(["--app-name=Plasma Addon Manager", "--", summary, message])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.as_slice() == ["--version"] {
        println!("plasma-addon-manager-agent {}", env!("CARGO_PKG_VERSION"));
        return ExitCode::SUCCESS;
    }
    if args.as_slice() != ["run"] {
        eprintln!("Usage: plasma-addon-manager-agent run|--version");
        return ExitCode::from(2);
    }

    let preferences = automation::home()
        .and_then(|home| Settings::load(&home))
        .map(|settings| (settings.notify_on_success, settings.notify_on_error))
        .unwrap_or((false, true));

    match automation::run_background() {
        Ok(settings) => {
            if settings.automatic && preferences.0 {
                notify("Plasma Addon Manager", "Automatyczna aktualizacja dodatków zakończona.");
            }
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("Automatic KDE Store updates failed: {error:#}");
            if preferences.1 {
                notify("Błąd aktualizacji dodatków Plasma", "Sprawdź dziennik Plasma Addon Manager.");
            }
            ExitCode::FAILURE
        }
    }
}
