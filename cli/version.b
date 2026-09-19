// The one version string the binary carries.
//
// It mirrors the repository's VERSION file, and `tools/check_version.sh` fails
// the build if the two drift — the installers match on this number.
package cli

pub const CORTADO_VERSION: string = "0.1.1"
