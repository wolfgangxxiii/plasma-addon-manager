#!/usr/bin/env bash
set -euo pipefail

pam_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pam_build="${pam_root}/build/package-deb"
pam_dist="${pam_root}/dist"

for tool in cmake cpack ninja cargo dpkg-deb dpkg-shlibdeps file; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing Debian packaging tool: $tool" >&2
        exit 1
    }
done

cmake -S "$pam_root" -B "$pam_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$pam_build" --parallel 2
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    "$pam_build/bin/plasma-addon-manager" --self-test
mkdir -p "$pam_dist"
cpack --config "$pam_build/CPackConfig.cmake" -G DEB -B "$pam_dist"

pam_deb="${pam_dist}/plasma-addon-manager_0.1.0_amd64.deb"
test -s "$pam_deb" || {
    echo "CPack did not create the expected package: $pam_deb" >&2
    exit 1
}
dpkg-deb --info "$pam_deb"
dpkg-deb --contents "$pam_deb" | grep -E 'plasma-addon-(manager|helper)' >/dev/null
echo "DEB package ready: $pam_deb"
