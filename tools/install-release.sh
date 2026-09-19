#!/bin/sh
# Install the cortado command line for the current user.
#
#   curl -fsSL https://github.com/beans-lang/cortado/releases/latest/download/cortado-install.sh | sh
#
# POSIX sh on purpose, and the same shape as the Beans installer: this may be the
# first thing a machine runs, so it assumes no bash, jq, python, node or git. It
# needs curl or wget, tar, and one of sha256sum, shasum or openssl.
#
# Nothing is installed until the download has been checksummed, unpacked into a
# staging directory, and the binary in it has answered `--version`. A failure at
# any step leaves an existing installation exactly as it was.
set -eu

REPO=${CORTADO_INSTALL_REPO:-beans-lang/cortado}
MANIFEST_NAME=cortado-release-manifest.tsv

say() { printf '%s\n' "$*"; }
note() { printf 'cortado: %s\n' "$*"; }
die() { printf 'cortado: error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: cortado-install.sh [options]

  --version <v>      install this release instead of the latest (e.g. 0.1.1)
  --prefix <dir>     install here instead of $HOME/.cortado
  --target <triple>  force a Beans target instead of detecting one
  --with-skia        also install the prebuilt shared renderer (~20MB)
  --force            reinstall even when this version is already installed
  --no-modify-path   do not touch shell startup files
  --help             show this message

environment:
  CORTADO_HOME       same as --prefix
  CORTADO_VERSION    same as --version
  CORTADO_TARGET     same as --target
EOF
}

version=${CORTADO_VERSION:-}
prefix=${CORTADO_HOME:-}
target=${CORTADO_TARGET:-}
with_skia=0
force=0
modify_path=1

while [ $# -gt 0 ]; do
    case $1 in
        --version) [ $# -ge 2 ] || die "--version needs a value"; version=$2; shift 2 ;;
        --version=*) version=${1#*=}; shift ;;
        --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix=$2; shift 2 ;;
        --prefix=*) prefix=${1#*=}; shift ;;
        --target) [ $# -ge 2 ] || die "--target needs a value"; target=$2; shift 2 ;;
        --target=*) target=${1#*=}; shift ;;
        --with-skia) with_skia=1; shift ;;
        --force) force=1; shift ;;
        --no-modify-path) modify_path=0; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

[ -n "$prefix" ] || prefix=$HOME/.cortado
case $prefix in
    /*) ;;
    *) die "--prefix must be an absolute path, not '$prefix'" ;;
esac

# ---------------------------------------------------------------- temporaries
work=
# The trailing `:` matters. An EXIT trap whose last command fails replaces the
# script's exit status, so a cleanup with nothing to clean must not decide it.
cleanup() { [ -n "$work" ] && rm -rf "$work"; :; }
trap cleanup EXIT HUP INT TERM
work=$(mktemp -d "${TMPDIR:-/tmp}/cortado-install.XXXXXX") ||
    die "cannot create a temporary directory"

# ------------------------------------------------------------------- fetching
if command -v curl >/dev/null 2>&1; then
    downloader=curl
elif command -v wget >/dev/null 2>&1; then
    downloader=wget
else
    die "neither curl nor wget is installed; install one and run this again"
fi

fetch_attempts=${CORTADO_INSTALL_ATTEMPTS:-3}

fetch_once() {
    if [ "$downloader" = curl ]; then
        curl -fsSL --proto '=https' --tlsv1.2 \
             --connect-timeout 20 --speed-limit 1024 --speed-time 30 \
             -o "$2" "$1"
    else
        wget -q --https-only --timeout=30 --tries=1 -O "$2" "$1"
    fi
}

# A stalled transfer is the failure this has to survive, not a refused one, and
# curl will not retry error 56 — so the retry is a loop rather than a flag.
fetch() {
    from=$1 to=$2
    case $from in
        http://*|https://*)
            attempt=1
            while :; do
                fetch_once "$from" "$to" && return 0
                [ "$attempt" -ge "$fetch_attempts" ] && return 1
                sleep $((attempt * 2))
                attempt=$((attempt + 1))
            done
            ;;
        *)
            [ -f "$from" ] || return 1
            cp "$from" "$to" || return 1
            ;;
    esac
    return 0
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        die "no sha256 tool found; install coreutils, perl-shasum or openssl"
    fi
}

unpack() {
    case $1 in
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q "$1" -d "$2"
            else
                # bsdtar reads zip; plain GNU tar does not and says so.
                tar xf "$1" -C "$2"
            fi
            ;;
        *) tar xzf "$1" -C "$2" ;;
    esac
}

# ------------------------------------------------------------------- platform
kernel=$(uname -s 2>/dev/null || echo unknown)
machine=$(uname -m 2>/dev/null || echo unknown)

if [ -z "$target" ]; then
    case $kernel in
        Linux)
            case $machine in
                x86_64|amd64) target="x86_64-unknown-linux-gnu" ;;
                aarch64|arm64) target="aarch64-unknown-linux-gnu" ;;
            esac
            ;;
        Darwin)
            # Beans targets macOS on arm64 only, so an Intel Mac has no package
            # even though uname would let us name one.
            case $machine in
                arm64|aarch64) target="arm64-apple-darwin" ;;
            esac
            ;;
        MINGW*|MSYS*|CYGWIN*)
            case $machine in
                x86_64|amd64) target="x86_64-pc-windows-msvc" ;;
            esac
            ;;
    esac
fi

# --------------------------------------------------------------- the manifest
base=${CORTADO_INSTALL_BASE_URL:-}
base_is_ours=0
if [ -z "$base" ]; then
    base_is_ours=1
    if [ -n "$version" ]; then
        base="https://github.com/$REPO/releases/download/v$version"
    else
        base="https://github.com/$REPO/releases/latest/download"
    fi
fi
manifest=${CORTADO_INSTALL_MANIFEST:-$base/$MANIFEST_NAME}

fetch "$manifest" "$work/manifest.tsv" ||
    die "cannot download the release manifest from $manifest"

# version  target  os  arch  kind  asset  sha256
lookup() {
    awk -F '\t' -v want="$1" -v kind="$2" '
        /^#/ || NF < 7 { next }
        $2 == want && $5 == kind { print; found = 1; exit }
        END { exit found ? 0 : 1 }
    ' "$work/manifest.tsv"
}

row=
if [ -n "$target" ]; then
    row=$(lookup "$target" cli || true)
fi

if [ -z "$row" ]; then
    say "cortado: no released package matches this machine." >&2
    say "" >&2
    say "  operating system: $kernel" >&2
    say "  architecture:     $machine" >&2
    if [ -n "$target" ]; then
        say "  beans target:     $target" >&2
    else
        say "  beans target:     could not be determined" >&2
    fi
    say "" >&2
    say "Published targets:" >&2
    awk -F '\t' '!/^#/ && NF >= 7 && $5 == "cli" { printf "  %s\n", $2 }' \
        "$work/manifest.tsv" >&2
    say "" >&2
    say "Pick one explicitly with CORTADO_TARGET=<triple>, or build from source:" >&2
    say "  https://github.com/$REPO#installing" >&2
    exit 1
fi

release_version=$(printf '%s' "$row" | cut -f1)
# Pin the rest of this install to the release the manifest just named. Without a
# --version, `latest` moves, and a release published mid-install 404s every URL.
if [ "$base_is_ours" -eq 1 ]; then
    base="https://github.com/$REPO/releases/download/v$release_version"
fi
asset=$(printf '%s' "$row" | cut -f6)
expected_sha=$(printf '%s' "$row" | cut -f7)

if [ -n "$version" ] && [ "$version" != "$release_version" ]; then
    die "the manifest at $manifest publishes $release_version, not $version"
fi

skia_row=
if [ "$with_skia" -eq 1 ]; then
    skia_row=$(lookup "$target" skia || true)
    [ -n "$skia_row" ] ||
        die "no prebuilt shared renderer is published for $target
Build one from a checkout with tools/prepare_skia.py, or install without --with-skia."
fi

# ----------------------------------------------------------- already installed
if [ "$force" -eq 0 ] && [ -x "$prefix/bin/cortado" ]; then
    installed=$("$prefix/bin/cortado" --version 2>/dev/null || true)
    case $installed in
        *"$release_version"*)
            if [ "$with_skia" -eq 0 ] || [ -n "$(ls "$prefix"/lib/*cortado_skia_engine* 2>/dev/null)" ]; then
                note "cortado $release_version is already installed in $prefix"
                note "re-run with --force to reinstall"
                exit 0
            fi
            ;;
    esac
fi

# -------------------------------------------------------------------- download
note "downloading $asset"
fetch "$base/$asset" "$work/$asset" || die "cannot download $base/$asset"
actual_sha=$(sha256_of "$work/$asset")
if [ "$actual_sha" != "$expected_sha" ]; then
    die "checksum mismatch for $asset
  expected $expected_sha
  actual   $actual_sha
Nothing was installed."
fi
note "checksum verified"

mkdir "$work/stage"
unpack "$work/$asset" "$work/stage" ||
    die "cannot unpack $asset; nothing was installed"
unpacked=$(find "$work/stage" -mindepth 1 -maxdepth 1 -type d | head -1)
[ -n "$unpacked" ] || die "$asset does not contain a package directory"

if [ "$with_skia" -eq 1 ]; then
    skia_asset=$(printf '%s' "$skia_row" | cut -f6)
    skia_sha=$(printf '%s' "$skia_row" | cut -f7)
    note "downloading $skia_asset"
    fetch "$base/$skia_asset" "$work/$skia_asset" ||
        die "cannot download $base/$skia_asset"
    actual_sha=$(sha256_of "$work/$skia_asset")
    if [ "$actual_sha" != "$skia_sha" ]; then
        die "checksum mismatch for $skia_asset
  expected $skia_sha
  actual   $actual_sha
Nothing was installed."
    fi
    mkdir "$work/skia"
    unpack "$work/$skia_asset" "$work/skia" ||
        die "cannot unpack $skia_asset; nothing was installed"
    engine=$(find "$work/skia" -name '*cortado_skia_engine*' -type f | head -1)
    [ -n "$engine" ] || die "$skia_asset carries no engine library"
    mkdir -p "$unpacked/lib"
    cp "$engine" "$unpacked/lib/" || die "cannot stage the engine"
    note "shared renderer staged"
fi

# A Windows package launches through bin/cortado.cmd; elsewhere it is bin/cortado.
launcher=
if [ -x "$unpacked/bin/cortado" ]; then
    launcher="$unpacked/bin/cortado"
elif [ -f "$unpacked/bin/cortado.cmd" ]; then
    launcher="$unpacked/bin/cortado.cmd"
else
    die "$asset has no bin/cortado; nothing was installed"
fi

# The staged binary has to answer before anything is moved into place, so a
# corrupt or wrong-architecture download can never replace a working install.
staged=$("$launcher" --version 2>/dev/null) ||
    die "the downloaded cortado does not run on this machine ($machine); nothing was installed"
note "staged $staged"

# --------------------------------------------------------------------- install
parent=$(dirname "$prefix")
mkdir -p "$parent" || die "cannot create $parent"
previous=
if [ -e "$prefix" ]; then
    previous="$prefix.old-$$"
    mv "$prefix" "$previous" || die "cannot move the existing $prefix aside"
fi
if ! mv "$unpacked" "$prefix"; then
    [ -n "$previous" ] && mv "$previous" "$prefix"
    die "cannot install into $prefix"
fi
[ -n "$previous" ] && rm -rf "$previous"

# ------------------------------------------------------------------------ PATH
bin_dir="$prefix/bin"
line="export PATH=\"$bin_dir:\$PATH\""
updated=
already=
if [ "$modify_path" -eq 1 ]; then
    for profile in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$profile" ] || continue
        # Idempotent: an installation that already added this must not add it twice.
        if grep -Fq "$bin_dir" "$profile" 2>/dev/null; then
            already="${already:+$already }$profile"
            continue
        fi
        {
            printf '\n# added by the cortado installer\n'
            printf '%s\n' "$line"
        } >>"$profile" && updated="${updated:+$updated }$profile"
    done
    if [ -z "$updated" ] && [ -z "$already" ]; then
        {
            printf '\n# added by the cortado installer\n'
            printf '%s\n' "$line"
        } >>"$HOME/.profile" && updated="$HOME/.profile"
    fi
fi

# ---------------------------------------------------------------------- report
say ""
note "installed cortado $release_version into $prefix"
if [ "$with_skia" -eq 1 ]; then
    note "the shared renderer is in $prefix/lib; cortado exports CORTADO_SKIA_LIBRARY for you"
else
    note "the shared Skia renderer is not installed; add it with --with-skia"
fi
if [ -n "$updated" ]; then
    note "PATH updated in: $updated"
elif [ -n "$already" ]; then
    note "PATH already set in: $already"
fi
if [ -n "$updated" ] || [ -n "$already" ]; then
    note "a new terminal picks this up automatically; to enable cortado in this"
    note "shell right now, run:"
else
    note "add cortado to your PATH with:"
fi
say ""
say "    $line"
say ""

launcher_name=$(basename "$launcher")
PATH="$bin_dir:$PATH" "$prefix/bin/$launcher_name" --version ||
    die "the installed cortado did not run"
note "cortado needs beansc to build a project: https://github.com/beans-lang/beans"
note "start one with 'cortado init myapp'"
