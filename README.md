<div align="center">

<img src="assets/io.github.wolfgangxxiii.PlasmaAddonManager.svg" width="100" alt="Plasma Addon Manager logo" />

# Plasma Addon Manager

**One KDE Plasma 6 add-on manager for Linux distributions.**
**Jeden menedżer dodatków KDE Plasma 6 dla wielu dystrybucji.**

[![License: GPLv3+](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
![Stage](https://img.shields.io/badge/stage-0.4.3%20AppImage%20preview-orange)
![Stack](https://img.shields.io/badge/GUI-Qt6%20%2B%20Kirigami-3577c1)

</div>

## 🇬🇧 English

Plasma Addon Manager is a **Qt6/KDE Kirigami** frontend with a **Rust** helper for
[plasmoid-updater](https://github.com/uwuclxdy/plasmoid-updater). The goal is a single
application for KDE Plasma 6 on Bazzite, Fedora KDE, Debian, Kubuntu, KDE neon, Arch,
CachyOS, openSUSE and other Linux distributions.

> [!IMPORTANT]
> **Version 0.4.3 is a development preview with an opt-in background updater.**
> It installs `plasmoid-updater`, checks and manually updates add-ons, and now
> configures its own systemd user timer. Any existing Bazzite/Debian schedule is
> left intact until the user explicitly consents to migration.

### Implemented in this milestone

- Native Qt6 + Kirigami window following the Plasma desktop style.
- Adaptive layout, navigation, Polish/English UI (automatic locale or manual choice).
- Read-only distribution detection using `/etc/os-release` and `ID_LIKE`.
- Read-only checks for Plasma session, architecture and required commands.
- Installed add-on list via `plasmoid-updater list-installed`.
- Available update check via `plasmoid-updater check` (without applying updates).
- Structured installed add-on and update cards, including read-only system add-ons,
  update versions and per-add-on issues; compatible with upstream 0.2.1 text output
  and future JSON output.
- Dashboard showing updater/agent versions, agent repair needs, timer health,
  previous service result and next scheduled update.
- Full read-only automation configuration test (service/timer/agent, settings,
  prerequisites and KDE Store availability), separate from update preview.
- Live GUI process output during manual updates, with transient network retries
  for read-only inventory and update checks.
- A complete session-wide action log, including time-stamped starts, failures,
  successes and CLI output. It is kept until the app closes; only the Journal
  screen shows the full text. Other screens show a compact green/red result,
  which automatic status refreshes never overwrite.
- openSUSE-specific `bsdtar` package guidance, missing-prerequisite diagnostics,
  compact updater versions without license text, and optional system inventory
  without requesting an interactive `sudo` password.
- Read-only preview (`update --dry-run` where supported; otherwise `check`).
- Confirmed manual updates with `update --yes --no-restart-plasma`.
- One-click GUI installer for `plasmoid-updater`: verified upstream GitHub SHA-256,
  current-version preservation and atomic user-local installation without root.
- Bazzite prerequisite setup in the same GUI action: reuse an existing `bsdtar`
  or install `libarchive` through user-local Homebrew when missing (with consent).
- One-click `bsdtar` setup along with `plasmoid-updater` on other supported
  distributions: `bsdtar` via openSUSE/Zypper or Fedora/DNF,
  `libarchive-tools` via Debian/Ubuntu/APT, and `libarchive` via Arch/CachyOS/Pacman.
  System package installation requires the existing install confirmation and
  the desktop PolicyKit administrator prompt; no terminal password entry.
- Independent headless `plasma-addon-manager-agent` installed in `~/.local/bin`.
- User-level schedule every 6, 12 or 24 hours, with optional Plasma restart,
  upstream updater check and desktop notifications on success or failure.
- Import settings from the working Bazzite/Debian GUIs and preserve upstream
  `plasmoid-updater.toml` options while updating excluded packages.
- Back up old systemd units and require explicit consent to disable old timers;
  roll back files and timer states if the new configuration fails.
- Repair the new agent, start the service manually and inspect its journal.
- Bazzite/Linuxbrew detection and PATH support, ported from the working Bazzite GUI.
- AppImage bundles Qt Wayland EGL/client plugins and checks Kirigami's KDE plugin.
- Software Qt Quick rendering by default in the AppImage, avoiding broken host OpenGL contexts.
- Timer status and recent journal via `systemctl --user` and `journalctl --user`.
- Asynchronous process execution: the interface does not block during scans.
- Allow-listed helper commands: no shell interpretation or unexpected system writes.

The Qt GUI talks to a Rust helper. A separate Rust agent runs in systemd user
services even when the AppImage is closed. Neither needs administrator rights
for normal operation or makes changes to the atomic Bazzite OS image. Only
installing a missing system prerequisite on a mutable distribution may ask
for graphical administrator authorization.

### Building from source

Requirements:

- Linux with **KDE Plasma 6** and a C++17 toolchain.
- **Qt 6.5+**, Qt Quick, Qt Quick Controls 2, KDE Kirigami (KF6),
  `QQC2DesktopStyle`, `extra-cmake-modules` and CMake 3.24+.
- Stable Rust and Cargo.
- `plasmoid-updater` for listing add-ons and checking updates.
- systemd user services for the timer and journal pages.

Install the matching development packages using your distribution's package
manager (package names differ; see [KDE Kirigami documentation](https://develop.kde.org/docs/getting-started/kirigami/)).

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./build/bin/plasma-addon-manager
```

The build folder contains `plasma-addon-manager` (Qt frontend),
`plasma-addon-helper` (Rust backend) and `plasma-addon-manager-agent` (background agent).

To install locally using CMake:

```bash
sudo cmake --install build
```

Building and installing from source **only installs this application**. The
upstream `plasmoid-updater` is installed separately by choosing **Install** in
the GUI. The background agent is installed only after choosing **Save and apply**
in Automation.

### AppImage only — direct download

Download `Plasma-Addon-Manager-v0.4.3-x86_64.AppImage` directly from
[GitHub Releases](https://github.com/wolfgangxxiii/plasma-addon-manager/releases).
It is a standalone `.AppImage` download, **not a ZIP archive**. The
[AppImage build workflow](https://github.com/wolfgangxxiii/plasma-addon-manager/actions/workflows/appimage.yml)
smoke-tests the Qt/Kirigami window and publishes the file to Releases after a
successful build on `main`. The project no longer creates DEB or Flatpak
packages.

**On Bazzite KDE — no terminal needed:**

1. Open **Bazaar** and install **Gear Lever** if it is not already installed.
2. Download the AppImage from Releases and open it with **Gear Lever** in Dolphin.
3. Select **Integrate**. Launch **Plasma Addon Manager** from the KDE app menu.
4. Inside the app, choose **Install / check version** to set up `plasmoid-updater`.
5. Open **Automation**, choose an interval and **Save and apply**. An active
   old updater schedule requires an explicit migration checkbox.

This is the AppImage integration approach recommended in the
[Bazzite documentation](https://docs.bazzite.gg/Installing_and_Managing_Software/AppImage/).
Gear Lever is only an optional graphical AppImage manager; this project still
distributes **AppImage only**, not a Flatpak edition.

Alternatively, standard Linux file managers can run AppImages directly: in
**Dolphin → Properties → Permissions**, enable **Is executable**, then
double-click. Downloaded files do not automatically receive execute permission;
an AppImage cannot override this security rule before being launched.

Developers may also launch the AppImage on KDE Plasma (x86_64) via terminal:

```bash
chmod +x Plasma-Addon-Manager-v0.4.3-x86_64.AppImage
./Plasma-Addon-Manager-v0.4.3-x86_64.AppImage
```

To build it from source, run `bash scripts/build-appimage.sh` on a Linux x86_64
system with Qt6, Kirigami, Rust/Cargo and the documented build dependencies.
The output is placed in `dist/`. `linuxdeploy` and its Qt6 plugin are checked
against pinned SHA-256 values. Runtime behavior on different Plasma 6
distributions still needs validation.

**On openSUSE Tumbleweed KDE:** the AppImage itself starts without installing
additional system packages, but `plasmoid-updater` needs the **`bsdtar`**
utility to check or apply KDE Store updates. Choose the same **Install / check
version** button. It installs the official `bsdtar` package through Zypper
if missing. Approve the regular graphical PolicyKit administrator prompt.
No terminal commands or separate prerequisite button are required.
If graphical authorization is unavailable or cancelled, the application
reports the failure and does not silently proceed with updates.
Read-only system add-ons are omitted when scanning needs interactive admin
rights; user add-ons are still displayed.

### Helper commands and tests

```bash
cargo test --manifest-path backend/Cargo.toml
cargo run --manifest-path backend/Cargo.toml -- diagnose
cargo run --manifest-path backend/Cargo.toml -- inventory
cargo run --manifest-path backend/Cargo.toml -- check
cargo run --manifest-path backend/Cargo.toml -- dry-run
cargo run --manifest-path backend/Cargo.toml -- install
cargo run --manifest-path backend/Cargo.toml -- settings-show
cargo run --manifest-path backend/Cargo.toml -- timer
cargo run --manifest-path backend/Cargo.toml -- journal
```

The helper also provides `install` and `update`. Both require user confirmation
in the GUI. `install` downloads and verifies the upstream binary into the user
account; `update` changes user-installed KDE Store add-ons. `settings-save`
manages only the app-owned systemd **user** units. No system packages are updated.

### Roadmap

1. **0.1.0 — Foundation:** Qt6/Kirigami, Rust discovery and read-only screens.
   **0.1.1 — Bazzite fix:** Wayland/Kirigami packaging, preview and manual updates.
2. **0.2.0 — Installer:** SHA-256 verified user-local installer and terminal-free
   launch using Gear Lever on Bazzite.
3. **0.3.0 — Automation:** migrate safely from existing user services, manage
   `systemd --user` agent/timer, configuration, exclusions and notifications.
4. **0.4.0 — Add-on overview:** structured inventory and update cards, live
   progress, agent health dashboard and saved configuration checks.
   **0.4.1 — Session logging:** retain all actions until exit, with compact
   success/error messages on each screen and a dedicated Journal view.
   **0.4.2 — openSUSE:** dependency warnings, safe system inventory and a
   properly formatted updater version.
   **0.4.3 — Unified prerequisites:** install `bsdtar` through supported distro
   package managers with graphical authentication as part of the updater setup.
5. **0.5.0 — Reliability:** extended rollback/systemd integration tests, runtime
   recovery from KDE Store errors and UI regression tests.
6. **1.0.0 — Release:** verified AppImage on multiple Plasma 6 distributions,
   with bilingual documentation and runtime tests.

### Migration and safety

The original repositories remain unchanged:

- [Bazzite Plasmoid Updater GUI](https://github.com/wolfgangxxiii/bazzite-kde-installer-plasmoid-updater-gui)
- [Debian/Ubuntu Plasmoid Updater GUI](https://github.com/wolfgangxxiii/deb-kde-installer-plasmoid-updater-gui)

Older Bazzite/Debian service/timer files are never overwritten. Only after
explicit migration consent are *active* old timers disabled, with backup and
rollback safeguards. The old settings files are preserved, and a new agent
is installed under the distinct name `plasma-addon-manager-agent`.
The project does **not perform general operating-system updates**. Its scope
remains **KDE Store add-ons**. The single explicit installer action may install
the missing `bsdtar` prerequisite (and its package dependencies) through the
host package manager after PolicyKit authorization on mutable distributions.
The Bazzite/atomic image is never modified.

---

## 🇵🇱 Polski

**Plasma Addon Manager** to uniwersalny interfejs **Qt6/KDE Kirigami** z backendem
**Rust**, przeznaczony do zarządzania aktualizacjami dodatków KDE Plasma 6 przez
[plasmoid-updater](https://github.com/uwuclxdy/plasmoid-updater).

Docelowo ma działać na Bazzite, Fedora KDE, Debianie, Kubuntu, KDE neon, Arch,
CachyOS, openSUSE i innych systemach korzystających z Plasma 6.

> [!IMPORTANT]
> **Wersja 0.4.3 nadal jest testowa — ma automatyzację, przegląd dodatków, pełny dziennik sesji i wspólną instalację zależności.**
> Pobiera `plasmoid-updater` z GitHub, weryfikuje SHA-256, instaluje go
> w katalogu użytkownika i pozwala kontrolować oraz ręcznie aktualizować dodatki.
> Tworzy własny harmonogram `systemd --user`; wcześniejszych harmonogramów
> nie przejmuje bez Twojej wyraźnej zgody. Nie zmienia obrazu systemu Bazzite.

### Co już działa w kodzie?

- Natywne GUI Qt6/Kirigami z nawigacją i dopasowaniem do motywu Plasma.
- Polski, angielski i automatyczny wybór języka.
- Wykrywanie dystrybucji na podstawie `/etc/os-release`.
- Diagnostyka zależności i sesji KDE Plasma.
- Odczyt dodatków i dostępnych aktualizacji przez istniejący `plasmoid-updater`.
- Karty dodatków z nazwą, typem, wersją i dostępną aktualizacją; odczyt dodatków
  użytkownika i systemowych, bez modyfikowania pakietów systemowych.
- Obsługa aktualnego wyjścia tekstowego `plasmoid-updater 0.2.1` i nowszego JSON.
- Pulpit z wersją programu i agenta, stanem timera, wynikiem ostatniej usługi
  oraz ostrzeżeniem o wymaganej naprawie.
- Pełny test zapisanej konfiguracji automatyzacji: zależności, agent, timer,
  usługa, ustawienia i test odczytu KDE Store bez instalowania dodatków.
- Bieżące komunikaty podczas operacji oraz ponawianie błędów sieciowych podczas
  odczytu dodatków i sprawdzania aktualizacji.
- Kompletny dziennik wszystkich operacji od uruchomienia programu, z czasem,
  komunikatami i wynikami. Tylko ekran Dziennik pokazuje pełny tekst;
  pozostałe ekrany pokazują krótkie komunikaty zielone/czerwone. Automatyczne
  odświeżenie stanu nie usuwa ostatniego wyniku. Dziennik sesji znika dopiero
  po zamknięciu programu (historia usługi systemd jest przechowywana osobno).
- Wykrywanie brakującego `bsdtar`, podpowiedź instalacji pakietu openSUSE,
  prawidłowy czerwony wynik nieudanej diagnostyki, krótki numer wersji bez
  licencji oraz bezpieczny odczyt dodatków bez żądania hasła `sudo`.
- Instalacja brakującego `bsdtar` w tym samym kroku co `plasmoid-updater`:
  openSUSE (Zypper), Fedora (DNF), Debian/Ubuntu (APT), Arch/CachyOS (Pacman),
  Bazzite (Homebrew). Na systemach tradycyjnych może pojawić się graficzne
  okno PolicyKit z prośbą o autoryzację administratora.
- Podgląd stanu timera oraz ostatnich wpisów dziennika użytkownika.
- Bezpieczne sprawdzenie aktualizacji (kod wyjścia 100 oznacza znalezione aktualizacje).
- Symulacja (`--dry-run` lub `check`) i ręczna aktualizacja po zatwierdzeniu.
- Przycisk instalacji `plasmoid-updater` bez konsoli i sudo, weryfikacja SHA-256.
- Automatyczny agent i harmonogram aktualizacji co 6/12/24 godziny.
- Wykluczenia dodatków, powiadomienia KDE, opcjonalny restart Plasma i aktualizacja narzędzia.
- Bezpieczna migracja poprzednich harmonogramów: kopia zapasowa, zgoda użytkownika i przywracanie po błędzie.
- Naprawa agenta, ręczne uruchomienie usługi i podgląd logów.
- Wykrywanie `plasmoid-updater` z Linuxbrew na Bazzite, dołączone wtyczki Wayland EGL/Kirigami.
- Domyślne renderowanie programowe Qt Quick w AppImage; można je zmienić zmienną `QT_QUICK_BACKEND`.
- Asynchroniczna obsługa poleceń Rust bez blokowania interfejsu.

### Kompilacja

Zainstaluj Rust/Cargo, CMake, Ninja, Qt6, Kirigami KF6 i narzędzia
deweloperskie swojej dystrybucji, następnie wykonaj:

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./build/bin/plasma-addon-manager
```

Testy backendu:

```bash
cargo test --manifest-path backend/Cargo.toml
```

### AppImage — bez archiwum ZIP

Projekt przygotowuje **wyłącznie AppImage** dla systemów KDE Plasma na x86_64.
Pobierz gotowy plik `.AppImage` bezpośrednio z
[GitHub Releases](https://github.com/wolfgangxxiii/plasma-addon-manager/releases).
Nie trzeba pobierać archiwum ZIP z GitHub Actions.

**Na Bazzite nie potrzebujesz terminala:** otwórz **Bazaar** i zainstaluj
**Gear Lever** (jeśli go jeszcze nie ma). Następnie w **Dolphin** otwórz
pobrany `.AppImage` za pomocą Gear Lever, kliknij **Integruj** i uruchamiaj
Plasma Addon Manager z menu aplikacji KDE. W samym programie użyj przycisku
**Zainstaluj / sprawdź wersję**, aby zainstalować `plasmoid-updater`. Na karcie
**Automatyzacja** wybierz interwał i kliknij **Zapisz i zastosuj**. Jeśli stary
timer jest aktywny, zaznacz zgodę na jego bezpieczne przejęcie.

Można również bez Gear Lever: w Dolphin kliknij prawym przyciskiem plik,
wybierz **Właściwości → Uprawnienia → Jest wykonywalny**, a następnie otwórz
AppImage dwuklikiem. Jest to zabezpieczenie Linuksa, nie błąd aplikacji.

**Na openSUSE Tumbleweed:** plik AppImage uruchamia się bez dodatkowych
pakietów, lecz aktualizacje KDE Store wymagają **`bsdtar`**. Naciśnij zwykły
przycisk **Zainstaluj / sprawdź wersję**. Program sam doinstaluje pakiet
`bsdtar` przez Zypper; jeśli potrzeba uprawnień, pojawi się graficzne okno
PolicyKit. Nie trzeba wpisywać żadnego polecenia w terminalu ani używać
osobnego przycisku. Jeśli autoryzacja zostanie anulowana, program pokaże błąd.
Odczyt listy dodatków użytkownika nadal nie wymaga hasła administratora.

Wyłącznie dla osób preferujących terminal istnieje również możliwość:

```bash
chmod +x Plasma-Addon-Manager-v0.4.3-x86_64.AppImage
./Plasma-Addon-Manager-v0.4.3-x86_64.AppImage
```

Wersję testową można samodzielnie zbudować przez
`bash scripts/build-appimage.sh`. Po udanej kompilacji i teście uruchomienia
[GitHub Actions](https://github.com/wolfgangxxiii/plasma-addon-manager/actions/workflows/appimage.yml)
publikuje AppImage w Releases. Nie tworzymy już pakietów DEB ani Flatpak.

Kolejne etapy obejmą testy AppImage na wielu rzeczywistych dystrybucjach,
rozbudowane testy migracji systemd i dalsze dopracowanie obsługi błędów KDE Store.

**Program nie jest menedżerem aktualizacji systemu operacyjnego.** Wyjątkiem
jest instalacja niezbędnego pakietu `bsdtar` (i jego zależności) podczas
konfiguracji aktualizatora, po potwierdzeniu przez użytkownika.

---

## License / Licencja

Copyright © 2026 Szymon Bławat (wolfgangxxiii).

Licensed under **GNU GPL-3.0-or-later**, see [LICENSE](LICENSE). The upstream
`plasmoid-updater` project is independent and retains its own license and authors.
