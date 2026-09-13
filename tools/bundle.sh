#!/usr/bin/env bash
# Wraps a built binary as a macOS .app bundle.
#
#     tools/bundle.sh build/gallery "Gallery" com.example.gallery
#     open build/Gallery.app
#
# A bare Mach-O binary runs and shows a window, which is why cortado's examples
# work without this. What it does *not* get is a name in the Dock, a name in
# the menu bar, a place in Launch Services, a document type, an icon, or the
# ability to be signed and notarised — all of which come from being a bundle
# with an Info.plist. A program nobody can double-click is not shipped.
#
# **This script writes nothing.** It is `cortado publish --binary`, under the
# positional command line every caller of it already uses. There was a version
# of this that wrote the Info.plist itself, beside a `cortado publish` that
# wrote another one, and two programs writing one plist is two plists that
# agree until somebody adds a key to one. For a project — a directory with a
# `cortado.pot` in it — use `cortado publish`, which reads the name, the
# identifier, the icon and every usage description from the manifest instead of
# from a command line.
#
# Codesigning is ad-hoc by default (`-s -`), which is enough to run locally on
# Apple silicon and is *not* enough to distribute: that needs a Developer ID and
# notarisation, which need an account, so this does the part that can be
# automated and says so rather than pretending.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: tools/bundle.sh <binary> <Name> [bundle-id] [icon.icns] [KEY=sentence]..." >&2
    echo "" >&2
    echo "  KEY=sentence adds a usage description to the Info.plist, e.g." >&2
    echo "    NSCameraUsageDescription='to scan a receipt'" >&2
    echo "" >&2
    echo "  macOS kills a program that touches a privacy-gated framework" >&2
    echo "  without the matching key, on a later turn of the run loop, with" >&2
    echo "  nothing on stderr. cortado refuses to ask without one, so the" >&2
    echo "  key is what turns 'unavailable' into a real answer." >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The positional four, then any number of KEY=sentence pairs.
binary=""
name=""
identifier=""
icon=""
plist_args=()
for argument in "$@"; do
    case "$argument" in
        *=*)
            key="${argument%%=*}"
            sentence="${argument#*=}"
            if [[ "$key" != NS*UsageDescription ]]; then
                echo "bundle: $key is not a usage-description key — they all" >&2
                echo "        look like NSCameraUsageDescription." >&2
                exit 2
            fi
            if [[ -z "$sentence" ]]; then
                echo "bundle: $key has no sentence after the =. macOS shows it" >&2
                echo "        to the user, and an empty one is a prompt that" >&2
                echo "        does not say what for." >&2
                exit 2
            fi
            plist_args+=(--plist "$argument")
            ;;
        *)
            if [[ -z "$binary" ]]; then binary="$argument"
            elif [[ -z "$name" ]]; then name="$argument"
            elif [[ -z "$identifier" ]]; then identifier="$argument"
            elif [[ -z "$icon" ]]; then icon="$argument"
            else
                echo "bundle: too many positional arguments at '$argument'" >&2
                exit 2
            fi
            ;;
    esac
done

[[ -z "$identifier" ]] && identifier="com.example.$(echo "$name" | tr '[:upper:]' '[:lower:]')"

if [[ ! -f "$binary" ]]; then
    echo "bundle: $binary is not there" >&2
    exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "bundle: a .app is a macOS bundle and this is not macOS." >&2
    echo "        Windows wants an .exe beside a manifest; Linux wants a" >&2
    echo "        .desktop file. Those are separate scripts, unwritten." >&2
    exit 1
fi

# The version the plist carries, from the changelog, as it always was.
version="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$root/CHANGELOG.md" 2>/dev/null | head -1)"
[[ -z "$version" ]] && version="0.1.0"

# Find or build the one program that writes the bundle.
CORTADO_BIN="${CORTADO_BIN:-$root/build/cortado}"
if [[ ! -x "$CORTADO_BIN" ]]; then
    BEANSC="${BEANSC:-}"
    if [[ -z "$BEANSC" ]]; then
        for candidate in "${BEANS_ROOT:-}/build/beansc" "$root/../../beans/build/beansc" "$(command -v beansc || true)"; do
            [[ -n "$candidate" && -x "$candidate" ]] && { BEANSC="$candidate"; break; }
        done
    fi
    if [[ -z "$BEANSC" ]]; then
        echo "bundle: no beansc to build build/cortado with — set \$BEANSC" >&2
        exit 1
    fi
    (cd "$root" && "$BEANSC" build examples/cortado_cli.b -o build/cortado >/dev/null)
fi

icon_args=()
[[ -n "$icon" ]] && icon_args=(--icon "$icon")

"$CORTADO_BIN" publish \
    --binary "$binary" \
    --name "$name" \
    --identifier "$identifier" \
    --app-version "$version" \
    ${icon_args[@]+"${icon_args[@]}"} \
    ${plist_args[@]+"${plist_args[@]}"}

identity="${CORTADO_SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    echo "  signed ad-hoc — enough to run here, not enough to distribute:"
    echo "  that needs a Developer ID and notarisation."
fi
