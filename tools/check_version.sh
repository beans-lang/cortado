#!/usr/bin/env bash
# The binary's version string and the repository's VERSION file must agree.
#
# The installers match a release on the number `cortado --version` prints, so a
# stale constant publishes a package that can never be detected as installed.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
declared=$(sed -n 's/^cortado=//p' "$root/VERSION")
compiled=$(sed -n 's/.*CORTADO_VERSION: string = "\(.*\)".*/\1/p' "$root/cli/version.b")

if [[ -z "$declared" ]]; then
    echo "VERSION does not declare cortado=<version>" >&2
    exit 1
fi
if [[ -z "$compiled" ]]; then
    echo "cli/version.b does not declare CORTADO_VERSION" >&2
    exit 1
fi
if [[ "$declared" != "$compiled" ]]; then
    echo "version drift: VERSION says $declared, cli/version.b says $compiled" >&2
    exit 1
fi
echo "cortado $declared"
