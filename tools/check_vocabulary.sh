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

fail() {
    echo "$1" >&2
    echo "  bx/widgets.b and component/vocabulary.b have drifted." >&2
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
# a name the editor offers. A flag reaches `attribute_call` through
# `is_boolean_attribute` rather than by name, so both are read.
{
    sed -n '/pub fn attribute_call(/,/^}/p' "$markup" \
        | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/'
    sed -n '/pub fn is_boolean_attribute(/,/^}/p' "$markup" \
        | grep -o 'name == "[a-z_]*"' | sed 's/.*"\(.*\)"/\1/'
} | sort -u >"$root/build/.attrs.kinded"

if ! diff -u "$root/build/.attrs.markup" "$root/build/.attrs.kinded" >"$root/build/.attrs.kind.diff"; then
    cat "$root/build/.attrs.kind.diff" >&2
    fail "attribute_names() and attribute_call() disagree about which names exist:"
fi

echo "ok vocabulary: $(wc -l <"$root/build/.tags.markup" | tr -d ' ') tags, $(wc -l <"$root/build/.events.markup" | tr -d ' ') events, $(wc -l <"$root/build/.attrs.markup" | tr -d ' ') attributes, in both tables"
