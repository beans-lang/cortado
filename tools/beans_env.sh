# Point the BEANS_* roots at whatever $1 is. Sourced by the other tools, and by
# test.sh, so there is one answer to "where is the standard library".
#
# A tree-built beansc finds nothing for itself, so the roots are named here. An
# installed release names its own and keeps them somewhere else — lib/std, not
# stdlib/std — so a guessed root for one is a path that cannot exist, and the
# failure lands far away as "no module 'std.math'" against a cortado file that
# is perfectly fine. Five copies of this said it five ways; two of them wrong.
cortado_beans_env() {
    local compiler="$1"
    local tree
    tree=$(cd "$(dirname "$compiler")/.." && pwd -P) || return 1
    if [[ -f "$tree/runtime/beans_rt.c" ]]; then
        export BEANS_RUNTIME="$tree/runtime/beans_rt.c"
        export BEANS_STDLIB="$tree/stdlib/std"
        export BEANS_ENCODING="$tree/runtime/encoding"
        export BEANS_NET="$tree/runtime/net"
        export BEANS_LOG="$tree/runtime/log"
    elif [[ -f "$tree/bin/beans_rt.c" ]]; then
        # The launcher exports the rest; a caller that links by hand needs this.
        export BEANS_RUNTIME="$tree/bin/beans_rt.c"
    fi
    # Said here rather than left to the compiler, which reports a missing
    # standard library as a missing module against whichever file imported it.
    local standard="${BEANS_STDLIB:-$tree/lib/std}"
    if [[ ! -d "$standard/math" ]]; then
        echo "no Beans standard library at $standard" >&2
        echo "  (resolved from BEANSC=$compiler)" >&2
        return 1
    fi
}
