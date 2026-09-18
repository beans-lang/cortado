#!/usr/bin/env bash
# Focused native service tests. GTK-on-mac and Wine check adapters, not an
# Orca/NVDA session on the target OS.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/accessibility"
mkdir -p "$out"

if [[ "$(uname -s)" == Darwin ]]; then
    sources=()
    while read -r source; do sources+=("$root/$source"); done \
        < <(sed -n 's/^csrc macos "\(.*\)"$/\1/p' "$root/beans.pot")
    frameworks=()
    while read -r framework; do frameworks+=(-framework "$framework"); done \
        < <(sed -n 's/^link macos framework "\(.*\)"$/\1/p' "$root/beans.pot")
    clang -fno-objc-arc "${sources[@]}" "$root/tests/mac_shared_services.m" \
        "${frameworks[@]}" -o "$out/mac_shared_services"
    "$out/mac_shared_services"
fi

if pkg-config --exists gtk4 2>/dev/null; then
    clang -std=c11 -O1 -g -Wall -Wextra $(pkg-config --cflags gtk4) \
        -I "$root/src" -I "$root/src/gtk4" \
        "$root"/src/gtk4/*.c "$root/tests/gtk_shared_services.c" \
        $(pkg-config --libs gtk4) -lm -o "$out/gtk_shared_services"
    "$out/gtk_shared_services"
else
    echo "SKIP gtk accessibility: gtk4 is not installed"
fi

if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    libraries=()
    while read -r library; do libraries+=("-l$library"); done \
        < <(sed -n 's/^link windows library "\(.*\)"$/\1/p' "$root/beans.pot")
    x86_64-w64-mingw32-gcc -std=c11 -O1 -g -Wall -Wextra \
        -I "$root/src" -I "$root/src/win32" \
        "$root"/src/win32/*.c "$root/tests/win32_shared_services.c" \
        -o "$out/win32_shared_services.exe" \
        "${libraries[@]}" -lws2_32 -lmswsock -lbcrypt -luserenv \
        -lntdll -lsynchronization -lm
    if [[ -n "${CORTADO_WINE:-}" ]]; then
        "$CORTADO_WINE" "$out/win32_shared_services.exe"
    elif command -v wine64 >/dev/null 2>&1; then
        wine64 "$out/win32_shared_services.exe"
    elif command -v wine >/dev/null 2>&1; then
        wine "$out/win32_shared_services.exe"
    elif command -v docker >/dev/null 2>&1 && \
         docker info >/dev/null 2>&1 && \
         docker image inspect cortado-wine >/dev/null 2>&1; then
        docker run --rm --platform linux/amd64 -v "$out":/w -w /w cortado-wine \
            bash -lc 'Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
              server=$!; waited=0
              while [ ! -e /tmp/.X11-unix/X99 ] && [ "$waited" -lt 40 ]; do
                  sleep 0.25; waited=$((waited + 1))
              done
              DISPLAY=:99 WINEDEBUG=-all timeout 120 /usr/lib/wine/wine64 /w/win32_shared_services.exe
              answer=$?; kill "$server" 2>/dev/null || true; exit "$answer"'
    else
        echo "SKIP win32 run: PE built, no Wine runner is available"
    fi
else
    echo "SKIP win32 accessibility: mingw-w64 is not installed"
fi
