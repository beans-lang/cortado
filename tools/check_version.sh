#!/usr/bin/env bash
# Every version string in the tree and the VERSION file must agree.
#
# The installers match a release on the number `cortado --version` prints, and
# `cortado init` pins the tag `cortado.version()` names, so a stale constant
# either publishes an undetectable package or scaffolds against the last one.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
declared=$(sed -n 's/^cortado=//p' "$root/VERSION")
compiled=$(sed -n 's/.*CORTADO_VERSION: string = "\(.*\)".*/\1/p' "$root/cli/version.b")
library=$(sed -n 's/^ *return "\(.*\)"$/\1/p' "$root/cortado.b")

if [[ -z "$declared" ]]; then
    echo "VERSION does not declare cortado=<version>" >&2
    exit 1
fi
if [[ -z "$compiled" ]]; then
    echo "cli/version.b does not declare CORTADO_VERSION" >&2
    exit 1
fi
if [[ -z "$library" ]]; then
    echo "cortado.b does not declare a version" >&2
    exit 1
fi
if [[ "$declared" != "$compiled" ]]; then
    echo "version drift: VERSION says $declared, cli/version.b says $compiled" >&2
    exit 1
fi
# test.sh holds cli/scaffold.b's pinned tag against this one, so checking it
# here is what keeps the scaffold from pinning a release behind.
if [[ "$declared" != "$library" ]]; then
    echo "version drift: VERSION says $declared, cortado.b says $library" >&2
    exit 1
fi
echo "cortado $declared"
