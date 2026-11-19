#!/usr/bin/env bash
set -euo pipefail

pam_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pam_manifest="${pam_root}/io.github.wolfgangxxiii.PlasmaAddonManager.json"
pam_build="${pam_root}/build/package-flatpak"
pam_repo="${pam_root}/build/flatpak-repo"
pam_dist="${pam_root}/dist"
pam_bundle="${pam_dist}/Plasma-Addon-Manager-v0.1.0-x86_64.flatpak"

for tool in flatpak flatpak-builder; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing Flatpak packaging tool: $tool" >&2
        exit 1
    }
done
test "$(uname -m)" = x86_64 || {
    echo "The preview Flatpak bundle currently targets x86_64 only." >&2
    exit 1
}

mkdir -p "$pam_dist"
flatpak-builder --user --install-deps-from=flathub --force-clean \
    --repo="$pam_repo" "$pam_build" "$pam_manifest"
flatpak-builder --run "$pam_build" "$pam_manifest" \
    env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    plasma-addon-manager --self-test
flatpak build-bundle "$pam_repo" "$pam_bundle" \
    io.github.wolfgangxxiii.PlasmaAddonManager stable
test -s "$pam_bundle"
sha256sum "$pam_bundle"
echo "Flatpak bundle ready: $pam_bundle"
