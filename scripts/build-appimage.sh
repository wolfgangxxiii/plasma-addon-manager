#!/usr/bin/env bash
set -euo pipefail

pam_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pam_build="${pam_root}/build/package-appimage"
pam_appdir="${pam_root}/build/package-appimage-AppDir"
pam_tools="${pam_root}/build/appimage-tools"
pam_dist="${pam_root}/dist"

test "$(uname -m)" = x86_64 || {
    echo "The preview AppImage currently supports x86_64 only." >&2
    exit 1
}
for tool in cmake ninja cargo curl sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing AppImage packaging tool: $tool" >&2
        exit 1
    }
done
test ! -e "$pam_appdir" || {
    echo "Existing AppDir at $pam_appdir; move it aside before rebuilding." >&2
    exit 1
}

cmake -S "$pam_root" -B "$pam_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$pam_build" --parallel 2
DESTDIR="$pam_appdir" cmake --install "$pam_build"
test -x "$pam_appdir/usr/bin/plasma-addon-manager"
test -x "$pam_appdir/usr/libexec/plasma-addon-manager/plasma-addon-helper"

mkdir -p "$pam_tools" "$pam_dist"

# SHA-256 checksums of the upstream continuous releases on 2026-11-18.
# A release replacement intentionally fails closed until the digest is reviewed.
pam_linuxdeploy="${pam_tools}/linuxdeploy-x86_64.AppImage"
pam_qt_plugin="${pam_tools}/linuxdeploy-plugin-qt-x86_64.AppImage"
if test ! -f "$pam_linuxdeploy"; then
    curl --fail --location --silent --show-error --retry 3 \
        https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
        -o "$pam_linuxdeploy"
fi
if test ! -f "$pam_qt_plugin"; then
    curl --fail --location --silent --show-error --retry 3 \
        https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage \
        -o "$pam_qt_plugin"
fi
printf '%s  %s\n' \
    df908b19f1ed1cdafa79508d415aa12d6c56ce4d56d4149aa8c09286718706e5 "$pam_linuxdeploy" \
    cfc1055b2b9dbc08412b579f20990b7b41a17b61beaa5847dc9477c96c9e9617 "$pam_qt_plugin" \
    | sha256sum --check --status || {
    echo "linuxdeploy tool checksum mismatch; refusing to execute downloaded tools." >&2
    exit 1
}
chmod +x "$pam_linuxdeploy" "$pam_qt_plugin"

if command -v qmake6 >/dev/null 2>&1; then
    export QMAKE="$(command -v qmake6)"
elif test -x /usr/lib/qt6/bin/qmake; then
    export QMAKE=/usr/lib/qt6/bin/qmake
else
    echo "Qt6 qmake is needed to detect QML module paths." >&2
    exit 1
fi
export QML_SOURCES_PATHS="${pam_root}/qml"
export APPIMAGE_EXTRACT_AND_RUN=1
export OUTPUT="${pam_dist}/Plasma-Addon-Manager-v0.1.0-x86_64.AppImage"

# linuxdeploy's QML scanner sees the Kirigami import, but the KDE Quick
# Controls style is selected at runtime in C++ and is otherwise skipped.
pam_qml_dir="$("$QMAKE" -query QT_INSTALL_QML)"
pam_qt_plugins="$("$QMAKE" -query QT_INSTALL_PLUGINS)"
test -d "${pam_qml_dir}/org/kde/desktop" || {
    echo "Missing org.kde.desktop QML style; install qml6-module-org-kde-desktop." >&2
    exit 1
}
mkdir -p "${pam_appdir}/usr/qml/org/kde"
cp -a "${pam_qml_dir}/org/kde/desktop" "${pam_appdir}/usr/qml/org/kde/"

# Keep Kirigami's KDE platform-specific appearance rather than falling back
# to its generic style when this AppImage runs outside the build system.
pam_kirigami_style="${pam_qt_plugins}/kf6/kirigami/platform/org.kde.desktop.so"
test -f "$pam_kirigami_style" || {
    echo "Missing Kirigami KDE platform plugin: $pam_kirigami_style" >&2
    exit 1
}
mkdir -p "${pam_appdir}/usr/plugins/kf6/kirigami/platform"
cp -a "$pam_kirigami_style" "${pam_appdir}/usr/plugins/kf6/kirigami/platform/"

pam_platforms="${pam_qt_plugins}/platforms"
pam_extra_platforms=""
if test -f "${pam_platforms}/libqoffscreen.so"; then
    pam_extra_platforms="libqoffscreen.so"
fi
if test -f "${pam_platforms}/libqwayland.so"; then
    pam_extra_platforms="${pam_extra_platforms:+${pam_extra_platforms};}libqwayland.so"
elif test -f "${pam_platforms}/libqwayland-egl.so"; then
    pam_extra_platforms="${pam_extra_platforms:+${pam_extra_platforms};}libqwayland-egl.so;libqwayland-generic.so"
fi
export EXTRA_PLATFORM_PLUGINS="$pam_extra_platforms"

"$pam_linuxdeploy" --appdir "$pam_appdir" --plugin qt --output appimage
test -s "$OUTPUT"
test -f "${pam_appdir}/usr/qml/org/kde/desktop/Button.qml"
test -f "${pam_appdir}/usr/plugins/kf6/kirigami/platform/org.kde.desktop.so"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    "$OUTPUT" --self-test
sha256sum "$OUTPUT"
echo "AppImage ready: $OUTPUT"
