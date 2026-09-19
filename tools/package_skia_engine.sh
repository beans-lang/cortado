#!/usr/bin/env bash
# Build one prebuilt shared-renderer archive.
#
#   tools/package_skia_engine.sh <version> <beans-target-triple> <output-directory>
#
# The engine is the only part of cortado that is not Beans: a C++ bridge linked
# against a pinned Skia. Shipping it is what saves a user the 400MB SDK download
# and the cmake build that `tools/prepare_skia.py` otherwise does on their machine.
set -euo pipefail
export COPYFILE_DISABLE=1

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <version> <beans-target-triple> <output-directory>" >&2
    exit 2
fi

version=$1
target=$2
output=$3
case "$version:$target" in
    *[!A-Za-z0-9._:-]*|*:*:*)
        echo "version and target may contain only letters, digits, dot, dash and underscore" >&2
        exit 2
        ;;
esac

repo=$(cd "$(dirname "$0")/.." && pwd -P)
mkdir -p "$output"
output=$(cd "$output" && pwd -P)

declared=$(sed -n 's/^cortado=//p' "$repo/VERSION")
if [[ "$declared" != "$version" ]]; then
    echo "release version $version does not match VERSION ($declared)" >&2
    exit 2
fi

arch=${target%%-*}
case "$target" in
    *-apple-darwin) os=macos;   skia_arch=arm64; library=libcortado_skia_engine.dylib ;;
    *-unknown-linux-gnu)
        os=linux;   library=libcortado_skia_engine.so
        case "$arch" in x86_64) skia_arch=x64 ;; aarch64|arm64) skia_arch=arm64 ;;
            *) echo "no pinned Skia for $arch" >&2; exit 2 ;; esac ;;
    *-windows-msvc)
        os=windows; library=cortado_skia_engine.dll
        case "$arch" in x86_64) skia_arch=x64 ;; aarch64|arm64) skia_arch=arm64 ;;
            *) echo "no pinned Skia for $arch" >&2; exit 2 ;; esac ;;
    *) echo "cortado does not publish an engine for $target" >&2; exit 2 ;;
esac
skia_target="$os-$skia_arch"

python3 "$repo/tools/prepare_skia.py" --target "$skia_target"

built="$repo/build/skia/lib/$library"
[[ -f "$built" ]] || { echo "prepare_skia.py produced no $library" >&2; exit 1; }

release=$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["release"])' "$repo/skia/dependencies.json")

name="cortado-skia-engine-$version-$target"
work=$(mktemp -d "${TMPDIR:-/tmp}/cortado-engine.XXXXXX")
trap 'rm -rf "$work"' EXIT
root="$work/$name"
mkdir -p "$root/lib"

cp "$built" "$root/lib/$library"
chmod 0755 "$root/lib/$library"
cp "$repo/LICENSE" "$root/LICENSE"

{
    printf 'cortado=%s\n' "$version"
    printf 'target=%s\n' "$target"
    printf 'os=%s\n' "$os"
    printf 'arch=%s\n' "$arch"
    printf 'kind=skia\n'
    printf 'skia=%s\n' "$release"
    printf 'library=%s\n' "$library"
} >"$root/VERSION"

{
    printf '# cortado shared renderer %s for %s\n\n' "$version" "$target"
    printf 'Skia %s, prebuilt. Point cortado at it:\n\n' "$release"
    printf '```sh\nexport CORTADO_SKIA_LIBRARY="$PWD/%s/lib/%s"\n```\n\n' "$name" "$library"
    printf 'The installer places it for you:\n\n'
    printf '```sh\ncurl -fsSL .../cortado-install.sh | sh -s -- --with-skia\n```\n'
} >"$root/README.md"

if [[ "$os" == windows ]]; then
    archive="$output/$name.zip"
    rm -f "$archive"
    (cd "$work" && python3 -c '
import shutil, sys
shutil.make_archive(sys.argv[1][:-4], "zip", ".", sys.argv[2])' "$archive" "$name")
else
    archive="$output/$name.tar.gz"
    rm -f "$archive"
    (cd "$work" && tar czf "$archive" "$name")
fi
printf '%s\n' "$archive"
