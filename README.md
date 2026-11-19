<div align="center">

<img src="assets/io.github.wolfgangxxiii.PlasmaAddonManager.svg" width="100" alt="Plasma Addon Manager logo" />

# Plasma Addon Manager

**One KDE Plasma 6 add-on manager for Linux distributions.**
**Jeden menedżer dodatków KDE Plasma 6 dla wielu dystrybucji.**

[![License: GPLv3+](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
![Stage](https://img.shields.io/badge/stage-0.1.0%20foundation-orange)
![Stack](https://img.shields.io/badge/GUI-Qt6%20%2B%20Kirigami-3577c1)

</div>

## 🇬🇧 English

Plasma Addon Manager is a **Qt6/KDE Kirigami** frontend with a **Rust** helper for
[plasmoid-updater](https://github.com/uwuclxdy/plasmoid-updater). The goal is a single
application for KDE Plasma 6 on Bazzite, Fedora KDE, Debian, Kubuntu, KDE neon, Arch,
CachyOS, openSUSE and other Linux distributions.

> [!IMPORTANT]
> **Version 0.1.0 is an initial, read-only development foundation, not a full replacement**
> for the existing Bazzite and Debian/Ubuntu applications. It cannot install the
> updater, edit schedules or update add-ons yet. The AppImage is a
> **development preview**.

### Implemented in this milestone

- Native Qt6 + Kirigami window following the Plasma desktop style.
- Adaptive layout, navigation, Polish/English UI (automatic locale or manual choice).
- Read-only distribution detection using `/etc/os-release` and `ID_LIKE`.
- Read-only checks for Plasma session, architecture and required commands.
- Installed add-on list via `plasmoid-updater list-installed`.
- Available update check via `plasmoid-updater check` (without applying updates).
- Existing timer status and recent journal via `systemctl --user` and `journalctl --user`.
- Asynchronous process execution: the interface does not block during scans.
- Allow-listed helper commands: no shell interpretation or unexpected system writes.

The GUI speaks to a separate Rust helper. The boundary is intentional: the
Rust backend can later be extended with distribution adapters while keeping
the native KDE interface independent of package managers.

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

The resulting build folder contains `plasma-addon-manager` (Qt frontend) and
`plasma-addon-helper` (Rust read-only backend).

To install locally using CMake:

```bash
sudo cmake --install build
```

Building and installing from source **only installs this application**, not
`plasmoid-updater` or a background agent. The Rust helper requires no root
privileges to inspect its supported resources.

### AppImage only — direct download

Download `Plasma-Addon-Manager-v0.1.0-x86_64.AppImage` directly from
[GitHub Releases](https://github.com/wolfgangxxiii/plasma-addon-manager/releases).
It is a standalone `.AppImage` download, **not a ZIP archive**. The
[AppImage build workflow](https://github.com/wolfgangxxiii/plasma-addon-manager/actions/workflows/appimage.yml)
smoke-tests the Qt/Kirigami window and publishes the file to Releases after a
successful build on `main`. The project no longer creates DEB or Flatpak
packages.

To run the AppImage on KDE Plasma (x86_64):

```bash
chmod +x Plasma-Addon-Manager-v0.1.0-x86_64.AppImage
./Plasma-Addon-Manager-v0.1.0-x86_64.AppImage
```

To build it from source, run `bash scripts/build-appimage.sh` on a Linux x86_64
system with Qt6, Kirigami, Rust/Cargo and the documented build dependencies.
The output is placed in `dist/`. `linuxdeploy` and its Qt6 plugin are checked
against pinned SHA-256 values. Runtime behavior on different Plasma 6
distributions still needs validation.

### Helper commands and tests

```bash
cargo test --manifest-path backend/Cargo.toml
cargo run --manifest-path backend/Cargo.toml -- diagnose
cargo run --manifest-path backend/Cargo.toml -- inventory
cargo run --manifest-path backend/Cargo.toml -- check
cargo run --manifest-path backend/Cargo.toml -- timer
cargo run --manifest-path backend/Cargo.toml -- journal
```

The helper intentionally accepts only `diagnose`, `inventory`, `check`, `timer`
and `journal`. `update`, `install` and other modifying operations **are not**
available in this release.

### Roadmap

1. **0.1.0 — Foundation:** Qt6/Kirigami, Rust discovery and read-only screens.
2. **0.2.0 — Compatibility:** shared installer for `plasmoid-updater`, SHA-256
   verification, existing-install preservation and distro-specific prerequisites.
3. **0.3.0 — Automation:** migrate safely from existing user services, manage
   `systemd --user` agent/timer, configuration, exclusions and notifications.
4. **0.4.0 — Add-on updates:** update workflow, clear progress, rollback safeguards,
   recovery from KDE Store errors and UI/regression tests.
5. **1.0.0 — Release:** verified AppImage on multiple Plasma 6 distributions,
   with bilingual documentation and runtime tests.

### Migration and safety

The original repositories remain unchanged:

- [Bazzite Plasmoid Updater GUI](https://github.com/wolfgangxxiii/bazzite-kde-installer-plasmoid-updater-gui)
- [Debian/Ubuntu Plasmoid Updater GUI](https://github.com/wolfgangxxiii/deb-kde-installer-plasmoid-updater-gui)

Until a documented migration procedure is implemented, do **not** install the
new app over an existing installation expecting it to manage the old agent.
The project never intends to update system packages (APT, DNF, Pacman,
rpm-ostree/bootc, etc.): its scope is **KDE Store add-ons**.

---

## 🇵🇱 Polski

**Plasma Addon Manager** to uniwersalny interfejs **Qt6/KDE Kirigami** z backendem
**Rust**, przeznaczony do zarządzania aktualizacjami dodatków KDE Plasma 6 przez
[plasmoid-updater](https://github.com/uwuclxdy/plasmoid-updater).

Docelowo ma działać na Bazzite, Fedora KDE, Debianie, Kubuntu, KDE neon, Arch,
CachyOS, openSUSE i innych systemach korzystających z Plasma 6.

> [!IMPORTANT]
> **Wersja 0.1.0 to wczesna wersja rozwojowa, wyłącznie do odczytu.** Nie jest
> jeszcze zamiennikiem dotychczasowych aplikacji. Nie instaluje narzędzia,
> nie zmienia harmonogramu i nie wykonuje aktualizacji dodatków.
> AppImage jest obecnie wersją **testową**.

### Co już działa w kodzie?

- Natywne GUI Qt6/Kirigami z nawigacją i dopasowaniem do motywu Plasma.
- Polski, angielski i automatyczny wybór języka.
- Wykrywanie dystrybucji na podstawie `/etc/os-release`.
- Diagnostyka zależności i sesji KDE Plasma.
- Odczyt dodatków i dostępnych aktualizacji przez istniejący `plasmoid-updater`.
- Podgląd stanu timera oraz ostatnich wpisów dziennika użytkownika.
- Asynchroniczne, **niemodyfikujące systemu** polecenia backendu Rust.

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

```bash
chmod +x Plasma-Addon-Manager-v0.1.0-x86_64.AppImage
./Plasma-Addon-Manager-v0.1.0-x86_64.AppImage
```

Wersję testową można samodzielnie zbudować przez
`bash scripts/build-appimage.sh`. Po udanej kompilacji i teście uruchomienia
[GitHub Actions](https://github.com/wolfgangxxiii/plasma-addon-manager/actions/workflows/appimage.yml)
publikuje AppImage w Releases. Nie tworzymy już pakietów DEB ani Flatpak.

Kolejne etapy obejmą instalację z SHA-256, bezpieczną migrację istniejącego
agenta, harmonogram 6/12/24 godzin, powiadomienia, aktualizacje KDE Store,
obsługę awarii sieci i testy AppImage na wielu dystrybucjach.

**Program nie jest menedżerem aktualizacji systemu operacyjnego.**

---

## License / Licencja

Copyright © 2026 Szymon Bławat (wolfgangxxiii).

Licensed under **GNU GPL-3.0-or-later**, see [LICENSE](LICENSE). The upstream
`plasmoid-updater` project is independent and retains its own license and authors.
