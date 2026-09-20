#!/usr/bin/env bash
# Build one public cortado command-line archive.
#
#   tools/package_release.sh <version> <beans-target-triple> <output-directory>
#
# The archive is exactly what a user downloads and unpacks: the two binaries, a
# relocatable launcher that finds a bundled Skia engine, and a VERSION file that
# is the only place the release manifest reads its platform columns from.
#
# Environment:
#   BEANSC      compiler to build with (default: the usual search)
#   CORTADO_PACKAGE_SKIA  a prebuilt engine library to place in lib/
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
# The number the binary prints is what an installer matches on, so a package is
# never built from a source tree whose constant has drifted.
bash "$repo/tools/check_version.sh" >/dev/null

# The triple is the single source of truth for the platform columns the manifest
# publishes and the installers match on, so it is parsed and never guessed.
arch=${target%%-*}
case "$target" in
    *-apple-darwin)   os=macos ;;
    *-linux-gnu|*-linux-musl|*-unknown-linux*) os=linux ;;
    *-windows-msvc|*-windows-gnu*)             os=windows ;;
    *) echo "cortado does not publish for $target" >&2; exit 2 ;;
esac

BEANSC="${BEANSC:-}"
if [[ -z "$BEANSC" ]]; then
    # A Windows release launches through beansc.cmd, which `command -v beansc`
    # does not find: Git Bash does not apply PATHEXT the way cmd.exe does.
    for candidate in "${BEANS_ROOT:-}/build/beansc" "$repo/../../beans/build/beansc" \
                     "$(command -v beansc || true)" "$(command -v beansc.cmd || true)" \
                     "$(command -v beansc.exe || true)"; do
        [[ -n "$candidate" && -x "$candidate" ]] && { BEANSC="$candidate"; break; }
    done
fi
[[ -n "$BEANSC" ]] || { echo "package: no beansc — set \$BEANSC" >&2; exit 1; }

# A tree-built beansc resolves its roots relative to the working directory, and
# this builds from cortado's. An installed release exports its own.
source "$repo/tools/beans_env.sh"
cortado_beans_env "$BEANSC" || exit 1

name="cortado-$version-$target"
work=$(mktemp -d "${TMPDIR:-/tmp}/cortado-package.XXXXXX")
trap 'rm -rf "$work"' EXIT
root="$work/$name"
mkdir -p "$root/bin" "$root/libexec" "$root/lib"

suffix=""
[[ "$os" == windows ]] && suffix=.exe

# Release, because this is the copy people run rather than the one they debug.
(cd "$repo" && "$BEANSC" build --release examples/cortado_cli.b \
    -o "$root/libexec/cortado$suffix")
(cd "$repo" && "$BEANSC" build --release examples/cortado_bx.b \
    -o "$root/libexec/cortado-bx$suffix")
chmod 0755 "$root/libexec/cortado$suffix" "$root/libexec/cortado-bx$suffix"

engine_name=""
case "$os" in
    macos)   engine_name=libcortado_skia_engine.dylib ;;
    linux)   engine_name=libcortado_skia_engine.so ;;
    windows) engine_name=cortado_skia_engine.dll ;;
esac
if [[ -n "${CORTADO_PACKAGE_SKIA:-}" ]]; then
    [[ -f "$CORTADO_PACKAGE_SKIA" ]] ||
        { echo "no engine at $CORTADO_PACKAGE_SKIA" >&2; exit 1; }
    cp "$CORTADO_PACKAGE_SKIA" "$root/lib/$engine_name"
fi

cp "$repo/LICENSE" "$root/LICENSE"
cp "$repo/README.md" "$root/README.md"

# The launcher is POSIX sh and resolves every path from its own location, so the
# whole installation can be moved after it is unpacked.
write_launcher() {
    local tool=$1
    cat >"$root/bin/$tool" <<EOF
#!/bin/sh
set -eu
# Only shell built-ins are used to find the installation. A launcher that calls
# dirname cannot start on a machine whose PATH is broken.
case \$0 in
    */*) bin=\${0%/*} ;;
    *)   bin=. ;;
esac
bin=\$(CDPATH= cd -- "\$bin" && pwd -P)
root=\$(CDPATH= cd -- "\$bin/.." && pwd -P)
CORTADO_HOME=\${CORTADO_HOME:-\$root}
export CORTADO_HOME
# An app built or launched from here inherits the engine this package shipped.
# Without it the shared renderer falls back to a source-relative path and fails.
if [ -z "\${CORTADO_SKIA_LIBRARY:-}" ] && [ -f "\$root/lib/$engine_name" ]; then
    CORTADO_SKIA_LIBRARY="\$root/lib/$engine_name"
    export CORTADO_SKIA_LIBRARY
fi
if [ "\${1-}" = upgrade ]; then
    if [ "\$#" -ne 1 ]; then
        echo "usage: $tool upgrade" >&2
        exit 2
    fi
    exec sh "\$root/libexec/cortado-install.sh" --prefix "\$root" --no-modify-path
fi
exec "\$root/libexec/$tool" "\$@"
EOF
    chmod 0755 "$root/bin/$tool"
}

write_windows_launcher() {
    local tool=$1
    cat >"$root/bin/$tool.cmd" <<EOF
@echo off
setlocal
set "CORTADO_ROOT=%~dp0.."
if not defined CORTADO_HOME set "CORTADO_HOME=%CORTADO_ROOT%"
set "CORTADO_ENGINE=%CORTADO_ROOT%\\lib\\$engine_name"
if not defined CORTADO_SKIA_LIBRARY if exist "%CORTADO_ENGINE%" set "CORTADO_SKIA_LIBRARY=%CORTADO_ENGINE%"
"%CORTADO_ROOT%\\libexec\\$tool.exe" %*
exit /b %ERRORLEVEL%
EOF
}

cp "$repo/tools/install-release.sh" "$root/libexec/cortado-install.sh"
cp "$repo/tools/install-release.ps1" "$root/libexec/cortado-install.ps1"
chmod 0755 "$root/libexec/cortado-install.sh"

for tool in cortado cortado-bx; do
    if [[ "$os" == windows ]]; then
        write_windows_launcher "$tool"
    else
        write_launcher "$tool"
    fi
done

{
    printf 'cortado=%s\n' "$version"
    printf 'target=%s\n' "$target"
    printf 'os=%s\n' "$os"
    printf 'arch=%s\n' "$arch"
    printf 'kind=cli\n'
    printf 'skia_bundled=%s\n' \
        "$([[ -f "$root/lib/$engine_name" ]] && echo yes || echo no)"
} >"$root/VERSION"

{
    printf '# cortado %s for %s\n\n' "$version" "$target"
    printf 'Unpack anywhere and add `bin` to your PATH:\n\n'
    printf '```sh\nexport PATH="$PWD/%s/bin:$PATH"\ncortado --version\n```\n\n' "$name"
    printf 'The one-line installer does this for you:\n\n'
    printf '```sh\ncurl -fsSL https://github.com/beans-lang/cortado/releases/latest/download/cortado-install.sh | sh\n```\n\n'
    printf 'Upgrade this installation later with `cortado upgrade`.\n'
} >"$root/INSTALL.md"

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
