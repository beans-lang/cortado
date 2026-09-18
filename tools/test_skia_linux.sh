#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
image=cortado-skia-linux:test
docker build --platform linux/amd64 -q -f tools/linux-skia.Dockerfile -t "$image" tools >/dev/null
docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src \
    -e EGL_PLATFORM=surfaceless -e LIBGL_ALWAYS_SOFTWARE=1 "$image" bash -lc '
        set -euo pipefail
        python3 tools/prepare_skia.py
        g++ -std=c++17 skia/tests/gpu/linux.cpp -Lbuild/skia/lib \
            -lcortado_skia_engine -lGL -Wl,-rpath,/src/build/skia/lib \
            -o build/skia-gpu-linux-test
        build/skia-gpu-linux-test
    '
