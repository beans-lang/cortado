#!/usr/bin/env bash
# Refuse a partial release.
#
#   tools/release_completeness.sh <manifest.tsv> <assets-dir>
#
# The list below is the release's promise. A target that silently stopped being
# built is the failure this exists to catch: the manifest would still be valid
# TSV and the installer would still work — for everyone except the people on the
# platform that vanished.
set -euo pipefail

manifest=${1:?usage: $0 <manifest.tsv> <assets-dir>}
assets=${2:?usage: $0 <manifest.tsv> <assets-dir>}

# Beans has no x86_64-apple-darwin target, so macOS is arm64 only and an Intel
# Mac is told that by the installer rather than offered a package.
expected=(
    "arm64-apple-darwin:cli"
    "arm64-apple-darwin:skia"
    "x86_64-unknown-linux-gnu:cli"
    "x86_64-unknown-linux-gnu:skia"
    "aarch64-unknown-linux-gnu:cli"
    "aarch64-unknown-linux-gnu:skia"
    "x86_64-pc-windows-gnullvm:cli"
    "x86_64-pc-windows-gnullvm:skia"
)

missing=0
for want in "${expected[@]}"; do
    target=${want%%:*}
    kind=${want##*:}
    row=$(awk -F '\t' -v t="$target" -v k="$kind" \
        '!/^#/ && $2 == t && $5 == k { print; exit }' "$manifest")
    if [[ -z "$row" ]]; then
        echo "missing from the manifest: $target ($kind)" >&2
        missing=1
        continue
    fi
    asset=$(printf '%s' "$row" | cut -f6)
    if [[ ! -f "$assets/$asset" ]]; then
        echo "the manifest names $asset, which is not in $assets" >&2
        missing=1
    fi
done

# Every file a user can download must also be in the manifest, or it is a stray
# artifact nobody checksummed.
while IFS= read -r file; do
    name=$(basename "$file")
    if ! awk -F '\t' -v a="$name" '!/^#/ && $6 == a { found = 1 } END { exit found ? 0 : 1 }' \
        "$manifest"; then
        echo "$name is in $assets but not in the manifest" >&2
        missing=1
    fi
done < <(find "$assets" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.zip' \))

if [[ "$missing" -ne 0 ]]; then
    echo "release is incomplete; nothing should be published" >&2
    exit 1
fi
printf 'every expected target is present (%s assets)\n' "${#expected[@]}"
