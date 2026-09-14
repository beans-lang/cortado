#!/usr/bin/env bash
# Holds bx/widgets.b and bx/events.b to component/vocabulary.b.
#
# cortado's markup vocabulary is written down twice, and there is one reason
# for it. `component/vocabulary.b` answers at run time, for components written
# by hand; `bx/widgets.b` answers at compile time, for components written in
# markup. They cannot be one table, because `cortado.bx` must build on a
# machine with no platform host — `cortado.component` reaches
# `cortado.host`'s foreign declarations, and a markup compiler that only built
# on macOS would be a markup compiler nobody on Windows could run.
#
# Two tables drift. A tag added to one and not the other is a control you can
# write in markup and not in Beans, or the reverse, and neither says so. This
# reads both and compares them.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/build"

runtime="$root/component/vocabulary.b"
markup="$root/bx/widgets.b"
events="$root/bx/events.b"

# `$2` names where to go and look. It is a second argument rather than one
# fixed line because this script checks two different pairs of tables now, and
# an error that sent somebody to bx/widgets.b over a missing accessibility role
# would cost them the time this gate was meant to save.
fail() {
    echo "$1" >&2
    echo "  ${2:-bx/widgets.b and component/vocabulary.b have drifted.}" >&2
    exit 1
}

# ---- tags ----
#
# The runtime table answers a WidgetKind per tag and groups several tags on one
# line, so every quoted name in `kind_of` counts.
sed -n '/pub static fn kind_of(/,/^    }/p' "$runtime" \
    | grep -o 'tag == "[A-Za-z]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.tags.runtime"
sed -n '/pub fn is_widget_tag(/,/^}/p' "$markup" \
    | grep -o 'tag == "[A-Za-z]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.tags.markup"

if ! diff -u "$root/build/.tags.runtime" "$root/build/.tags.markup" >"$root/build/.tags.diff"; then
    cat "$root/build/.tags.diff" >&2
    fail "a control tag is in one vocabulary and not the other:"
fi

# The list `cortado-bx vocabulary` prints has to match the predicate it
# describes, or an editor offers a tag the compiler refuses.
sed -n '/pub fn widget_tags(/,/^}/p' "$markup" \
    | grep -o '"[A-Za-z]*"' | sed 's/"//g' | sort -u >"$root/build/.tags.listed"
if ! diff -u "$root/build/.tags.markup" "$root/build/.tags.listed" >"$root/build/.tags.list.diff"; then
    cat "$root/build/.tags.list.diff" >&2
    fail "widget_tags() does not list what is_widget_tag() accepts:"
fi

# ---- events ----
sed -n '/pub static fn event_of(/,/^    }/p' "$runtime" \
    | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.events.runtime"
sed -n '/pub fn event_family(/,/^}/p' "$events" \
    | grep -o 'event == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.events.markup"

if ! diff -u "$root/build/.events.runtime" "$root/build/.events.markup" >"$root/build/.events.diff"; then
    cat "$root/build/.events.diff" >&2
    fail "an event name is in one vocabulary and not the other:"
fi

sed -n '/pub fn event_names(/,/^}/p' "$events" \
    | grep -o '"[a-z_]*"' | sed 's/"//g' | sort -u >"$root/build/.events.listed"
if ! diff -u "$root/build/.events.markup" "$root/build/.events.listed" >"$root/build/.events.list.diff"; then
    cat "$root/build/.events.list.diff" >&2
    fail "event_names() does not list what event_family() accepts:"
fi

# ---- attributes ----
#
# Every name the markup compiler accepts must be one the Builder can act on:
# a host property, one of the layout names, or `text`, which is the control's
# own text and has no property id.
{
    sed -n '/pub static fn property_of(/,/^    }/p' "$runtime" \
        | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/'
    sed -n '/pub static fn is_layout_name(/,/^    }/p' "$runtime" \
        | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/'
    echo text
} | sort -u >"$root/build/.attrs.runtime"

sed -n '/pub fn attribute_names(/,/^}/p' "$markup" \
    | grep -o '"[a-z_]*"' | sed 's/"//g' | sort -u >"$root/build/.attrs.markup"

if ! diff -u "$root/build/.attrs.runtime" "$root/build/.attrs.markup" >"$root/build/.attrs.diff"; then
    cat "$root/build/.attrs.diff" >&2
    fail "an attribute name is in one vocabulary and not the other:"
fi

# And every listed attribute must have a call kind, or the emitter would refuse
# a name the editor offers. Flags and colours reach `attribute_call` through a
# predicate rather than by name, so those are read too.
{
    for reader in attribute_call is_boolean_attribute is_colour_attribute; do
        sed -n "/pub fn $reader(/,/^}/p" "$markup" \
            | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/'
    done
} | sort -u >"$root/build/.attrs.kinded"

if ! diff -u "$root/build/.attrs.markup" "$root/build/.attrs.kinded" >"$root/build/.attrs.kind.diff"; then
    cat "$root/build/.attrs.kind.diff" >&2
    fail "attribute_names() and attribute_call() disagree about which names exist:"
fi

# ---- the framework's own attributes ----
# `bx/widgets.b` decides what the compiler treats as the framework's;
# `bx/vocabulary.b` publishes it. Nothing held them together, and three boolean
# names were missing from the published list the whole time.
vocabulary="$root/bx/vocabulary.b"

sed -n '/pub fn is_reserved_attribute(/,/^}/p' "$markup" \
    | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.reserved.markup"
sed -n '/pub fn reserved_attributes(/,/^}/p' "$vocabulary" \
    | grep -o 'new VocabRow("[a-z_]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.reserved.listed"
if [[ ! -s "$root/build/.reserved.markup" ]]; then
    fail "no reserved attributes were read from bx/widgets.b, so this check covered nothing:" \
         "Look for 'pub fn is_reserved_attribute(' in bx/widgets.b."
fi
if ! diff -u "$root/build/.reserved.markup" "$root/build/.reserved.listed" \
        >"$root/build/.reserved.diff"; then
    cat "$root/build/.reserved.diff" >&2
    echo "  < answered by is_reserved_attribute      > listed by reserved_attributes()" >&2
    fail "reserved_attributes() does not list what is_reserved_attribute() answers:" \
         "bx/widgets.b and bx/vocabulary.b have drifted."
fi

sed -n '/pub fn is_boolean_attribute(/,/^}/p' "$markup" \
    | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.bools.markup"
sed -n '/pub fn boolean_attributes(/,/^}/p' "$vocabulary" \
    | grep -o '"[a-z_]*"' | sed 's/"//g' | sort -u >"$root/build/.bools.listed"
if [[ ! -s "$root/build/.bools.markup" ]]; then
    fail "no boolean attributes were read from bx/widgets.b, so this check covered nothing:" \
         "Look for 'pub fn is_boolean_attribute(' in bx/widgets.b."
fi
if ! diff -u "$root/build/.bools.markup" "$root/build/.bools.listed" \
        >"$root/build/.bools.diff"; then
    cat "$root/build/.bools.diff" >&2
    echo "  < answered by is_boolean_attribute      > listed by boolean_attributes()" >&2
    fail "boolean_attributes() does not list what is_boolean_attribute() answers:" \
         "bx/widgets.b and bx/vocabulary.b have drifted."
fi

# Every listed attribute must carry a note: `attribute_note` ends in an empty
# string, so a name with none ships a blank description and nothing says so.
sed -n '/^fn attribute_note(/,/^}/p' "$vocabulary" \
    | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/' | sort -u >"$root/build/.attrs.noted"
if [[ ! -s "$root/build/.attrs.noted" ]]; then
    fail "no attribute notes were read from bx/vocabulary.b, so this check covered nothing:" \
         "Look for 'fn attribute_note(' in bx/vocabulary.b."
fi
if ! diff -u "$root/build/.attrs.markup" "$root/build/.attrs.noted" \
        >"$root/build/.attrs.noted.diff"; then
    cat "$root/build/.attrs.noted.diff" >&2
    echo "  < listed by attribute_names()      > described by attribute_note()" >&2
    fail "an attribute is published with no description, or described and not published:" \
         "attribute_note() ends in an empty string, so the editor would show a blank."
fi

# ---- property names in goldens ----
# `property_name` ends in `p{property}` on purpose, so a forgotten key prints as
# a number. Nine had reached the header and not it, and nothing was reading it.
runtime_attr="$root/component/attribute.b"

grep -oE '^pub const P_[A-Z_0-9]+' "$root/host/constants.b" \
    | sed 's/^pub const //' | sort -u >"$root/build/.props.declared"
sed -n '/^pub fn property_name(/,/^}/p' "$runtime_attr" \
    | grep -oE 'host\.P_[A-Z_0-9]+' | sed 's/^host\.//' | sort -u >"$root/build/.props.named"
if [[ ! -s "$root/build/.props.declared" ]]; then
    fail "no properties were read from host/constants.b, so this check covered nothing:" \
         "Look for 'pub const P_' in host/constants.b."
fi
if [[ ! -s "$root/build/.props.named" ]]; then
    fail "no properties were read from component/attribute.b, so this check covered nothing:" \
         "Look for 'pub fn property_name(' in component/attribute.b."
fi
if ! diff -u "$root/build/.props.declared" "$root/build/.props.named" \
        >"$root/build/.props.diff"; then
    cat "$root/build/.props.diff" >&2
    echo "  < declared in host/constants.b      > named by property_name()" >&2
    fail "a property has no readable name, so a golden would print it as a number:" \
         "Add it to property_name() in component/attribute.b, beside the others."
fi

# ---- an arm written twice ----
# beansc accepts an unreachable duplicate arm without complaint. Two were here,
# harmless only because the copies agreed; the next pair will not.
#
# Each label is tagged with its function: one name may appear in two matches in
# one file, and only a repeat inside one of them is the bug.
arm_labels() {
    # $1 file, $2 a regex matching one arm label.
    awk -v pattern="$2" '
        /^[[:space:]]*(pub )?(static )?fn [a-z_]+\(/ { current = $0; next }
        current == "" { next }
        {
            line = $0
            while (match(line, pattern)) {
                print current "\t" substr(line, RSTART, RLENGTH)
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

for pair in "$root/widgets/widget_kind.b|[a-z_]+ =>" "$runtime_attr|host\.P_[A-Z_0-9]+"; do
    file="${pair%%|*}"
    pattern="${pair##*|}"
    short="$(basename "$file")"
    arm_labels "$file" "$pattern" >"$root/build/.arms.$short"
    # The guard first: an extraction that stopped matching prints nothing, and
    # so does a clean file. Without it a broken pattern passes forever.
    if [[ ! -s "$root/build/.arms.$short" ]]; then
        fail "no match arms were read from $short, so this check covered nothing:" \
             "The pattern in this script no longer matches what $short is written like."
    fi
    sort "$root/build/.arms.$short" | uniq -d | cut -f2 >"$root/build/.dup.$short"
    if [[ -s "$root/build/.dup.$short" ]]; then
        cat "$root/build/.dup.$short" >&2
        fail "an arm is written twice in $short, and the second can never run:" \
             "Delete the copy. beansc does not refuse this, which is why the gate does."
    fi
done

# ---- widget kinds ----
#
# `WidgetKind.all()` is a hand-written list of the enum's own cases, and it is
# what `tests/enabled.b` walks. Nothing in Beans can enumerate an enum, so the
# list is the only way to walk the kinds — and a hand-written list of things
# declared six lines above it is exactly the sort of thing that goes one short
# and stays that way. `canvas` did: it reached the enum, never reached the
# walk, and the golden kept its old length looking perfectly healthy.
kinds="$root/widgets/widget_kind.b"
awk '/^pub enum WidgetKind \{/,/^    pub static fn all/' "$kinds" \
    | grep -oE '^    [a-z_][a-z_0-9]*$' | tr -d ' ' | sort -u >"$root/build/.kinds.declared"
sed -n '/pub static fn all(/,/^    }/p' "$kinds" \
    | grep -oE 'WidgetKind\.[a-z_][a-z_0-9]*' | sed 's/WidgetKind\.//' \
    | sort -u >"$root/build/.kinds.walked"

if [[ ! -s "$root/build/.kinds.declared" ]]; then
    fail "no widget kinds were read from the enum, so this check covered nothing:" \
         "Look for 'pub enum WidgetKind {' in widgets/widget_kind.b."
fi
if ! diff -u "$root/build/.kinds.declared" "$root/build/.kinds.walked" \
        >"$root/build/.kinds.diff"; then
    cat "$root/build/.kinds.diff" >&2
    echo "  < declared in the enum      > listed by all()" >&2
    fail "WidgetKind.all() does not list every kind the enum declares:" \
         "Add the case to all() in widgets/widget_kind.b, beside the others."
fi

# ---- accessibility roles ----
#
# Every widget kind must have a role in every host, and this is the one table
# that could not fail on its own. `ctd_a11y_role` is a C switch with a
# `default`, so a kind nobody added lands on the fallback and a screen reader
# calls a new control a window — no error, no warning, nothing in a golden that
# reads as wrong rather than as a choice.
#
# The Beans side needs no check of its own: `WidgetMaker.bare` is an exhaustive
# `match` over `WidgetKind`, so a kind with no case there is a compile error
# and the compiler is a better gate than this script.
grep -oE '^#define CTD_W_[A-Z_]+' "$root/src/cortado_host.h" \
    | sed 's/^#define //' | sort -u >"$root/build/.roles.header"

hosts_read=0
for directory in "$root"/src/*/; do
    [[ -d "$directory" ]] || continue
    name="$(basename "$directory")"
    # Only the files that are there. A glob that matches nothing expands to
    # itself, and `cat` on a literal `*.m` fails the pipeline — which under
    # `set -e` would read as "this host answered nothing", the exact silent
    # green this gate exists to prevent.
    present=()
    for source in "$directory"*.m "$directory"*.c; do
        [[ -e "$source" ]] && present+=("$source")
    done
    # The body of ctd_a11y_role in whichever file of this host defines it.
    sed -n '/ctd_a11y_role(ctd_handle/,/^}/p' "${present[@]}" \
        | { grep -oE 'CTD_W_[A-Z_]+' || true; } | sort -u >"$root/build/.roles.$name"
    if [[ ! -s "$root/build/.roles.$name" ]]; then
        fail "src/$name/ has no ctd_a11y_role to read, so this check covered nothing:" \
             "Look for the function this script greps for, not for a drifted table."
    fi
    # And whether it can build one. This is the answer that must not default:
    # a kind added to the header and forgotten in a host would fall through to
    # "not a kind" or, worse, to 0 — and 0 reads as "this platform hasn't got
    # one", which is a fact about Windows rather than about an omission.
    sed -n '/ctd_widget_supports(int32_t kind)/,/^}/p' "${present[@]}" \
        | { grep -oE 'CTD_W_[A-Z_]+' || true; } | sort -u >"$root/build/.builds.$name"
    if [[ ! -s "$root/build/.builds.$name" ]]; then
        fail "src/$name/ has no ctd_widget_supports to read, so this check covered nothing:" \
             "Look for the function this script greps for, not for a drifted table."
    fi
    if ! diff -u "$root/build/.roles.header" "$root/build/.builds.$name" \
            >"$root/build/.builds.$name.diff"; then
        cat "$root/build/.builds.$name.diff" >&2
        echo "  < declared in cortado_host.h      > answered by src/$name/" >&2
        fail "the $name host does not say yes or no for every widget kind:" \
             "Add the case to ctd_widget_supports in src/$name/, beside the others."
    fi
    if ! diff -u "$root/build/.roles.header" "$root/build/.roles.$name" \
            >"$root/build/.roles.$name.diff"; then
        cat "$root/build/.roles.$name.diff" >&2
        echo "  < declared in cortado_host.h      > answered by src/$name/" >&2
        fail "the $name host has no accessibility role for every widget kind:" \
             "Add the case to ctd_a11y_role in src/$name/, beside the others."
    fi
    hosts_read=$((hosts_read + 1))
done
if [[ $hosts_read -eq 0 ]]; then
    fail "no host directory was read for accessibility roles:" \
         "src/ has no platform directories, so this check covered nothing."
fi

echo "ok vocabulary: $(wc -l <"$root/build/.kinds.declared" | tr -d ' ') kinds, $(wc -l <"$root/build/.tags.markup" | tr -d ' ') tags, $(wc -l <"$root/build/.events.markup" | tr -d ' ') events, $(wc -l <"$root/build/.attrs.markup" | tr -d ' ') attributes ($(wc -l <"$root/build/.bools.markup" | tr -d ' ') boolean, $(wc -l <"$root/build/.reserved.markup" | tr -d ' ') reserved), $(wc -l <"$root/build/.roles.header" | tr -d ' ') roles and as many yes-or-no answers in $hosts_read hosts, in both tables"
