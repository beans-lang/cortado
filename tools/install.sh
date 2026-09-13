#!/usr/bin/env bash
# Builds `cortado` and puts it where a shell will find it.
#
#     tools/install.sh                    # into $BEANS_HOME/bin, or ~/.beans/bin
#     tools/install.sh /usr/local/bin     # somewhere else
#
# `cortado init` has to run before a project exists, so the one thing it cannot
# do is be found through a project's own dependencies. That is what this is
# for.
#
# `cortado-bx` goes in beside it. It is the same program under its older name —
# `cortado generate` — and it is installed because the editors' vocabulary and
# a good deal of writing still name it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BEANSC="${BEANSC:-}"
if [[ -z "$BEANSC" ]]; then
    for candidate in "${BEANS_ROOT:-}/build/beansc" "$root/../../beans/build/beansc" "$(command -v beansc || true)"; do
        [[ -n "$candidate" && -x "$candidate" ]] && { BEANSC="$candidate"; break; }
    done
fi
if [[ -z "$BEANSC" ]]; then
    echo "install: no beansc — set \$BEANSC, or build one in ../../beans" >&2
    exit 1
fi

target="${1:-}"
if [[ -z "$target" ]]; then
    home="${BEANS_HOME:-$HOME/.beans}"
    target="$home/bin"
fi
mkdir -p "$target"

# Release, because this is the copy people run rather than the one they debug.
(cd "$root" && "$BEANSC" build --release examples/cortado_cli.b -o build/cortado)
(cd "$root" && "$BEANSC" build --release examples/cortado_bx.b -o build/cortado-bx)

# **Never `cp` over an existing compiler binary on macOS.** The stale signature
# cache makes the kernel SIGKILL the new binary with no message at all; `rm -f`
# first is what the beans Makefile does and for the same reason.
for name in cortado cortado-bx; do
    rm -f "$target/$name"
    cp "$root/build/$name" "$target/$name"
    chmod +x "$target/$name"
done

echo "installed cortado and cortado-bx into $target"
case ":$PATH:" in
    *":$target:"*) ;;
    *) echo "  $target is not on your PATH" ;;
esac
