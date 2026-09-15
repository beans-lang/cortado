// vocabulary.b — cortado's `.bx` surface, as data an editor can read.
//
// An editor cannot ask cortado-bx what a `.bx` file may contain: the extension
// is a TypeScript bundle and cortado-bx is a Beans binary. So the vocabulary
// is **printed** from here and checked in on the editor side.
// `cortado-bx vocabulary` prints it for a person regenerating it by hand, and
// the gate diffs the printed JSON against the committed copy.
//
// **Why the lists are written out and not derived.** The predicates in
// `widgets.b` and `events.b` are chains of `==`, and a chain cannot be
// enumerated. So `tools/check_vocabulary.sh` reads both the predicate and the
// list out of the source and diffs them: a row added to `widgets.b` and
// forgotten here fails the build rather than shipping an editor that has never
// heard of it, and the reverse fails too. Every list in this file that mirrors
// a predicate is in that gate — `controls`, `attributes`,
// `boolean_attributes`, `reserved_attributes` and the events — and a new one
// belongs there the day it is written, not the day it is found wrong.
//
// Nothing under cortado's module root imports this file, and neither does the
// emitter. It is data about the language, for a reader outside it.

package bx

/// One named thing in the surface, with the form to write and why.
///
/// Three strings rather than a shape per section: an editor renders `name` in
/// the list, `detail` beside it and `note` in the hover, and every section
/// answers those three.
pub class VocabRow {
    pub name: string = ""
    pub detail: string = ""
    pub note: string = ""
    pub fn init(name: string, detail: string, note: string) {
        self.name = name
        self.detail = detail
        self.note = note
    }
}

/// The `$` blocks. `else` is in the list and carries no `$`, because that is
/// how it is written: `$if c { } else { }` (`parse_if`).
pub fn blocks() -> List<VocabRow> {
    return [
        new VocabRow("$if", r#"$if <expr> { ... }"#,
                     r#"A branch, emitted as a Beans if. A branch that is not taken contributes no element, so the siblings after it shift — give them key={ } if that matters."#),
        new VocabRow("else", r#"$if <expr> { ... } else if <expr> { ... } else { ... }"#,
                     "Written without a $, because it continues the $if that opened the block."),
        new VocabRow("$for", r#"$for <name> in <expr> { ... }"#,
                     r#"A loop, emitted as a Beans for. A child carrying key={ } keeps its control across reordering; without one, rows match by position."#),
        new VocabRow("$match", r#"$match <expr> { <pattern> => { ... } }"#,
                     "A branch with more than two arms. At least one arm is required."),
        new VocabRow("$slot", r#"$slot | $slot(<expr>) | $slot:<name> | $slot:<name> as <expr> | $slot:<name> { ... } | $slot:<name> as <p>: <Type> { ... }"#,
                     "Places or defines a template. A body makes it a definition and only reads that way inside a component tag; the other four place one, and a component declares each template as an fn(Builder) field."),

    ]
}

/// The three interpolation forms, and the escape.
pub fn interpolations() -> List<VocabRow> {
    return [
        new VocabRow("$<chain>", "$self.count, $row.title, $self.rows[0]",
                     "An implicit chain. It ends where the chain ends, so $5.00 and US$ are ordinary text."),
        new VocabRow(r#"$( )"#, "$(a + b)",
                     "A parenthesised expression. One line: a newline inside it is refused."),
        new VocabRow(r#"${ }"#, r#"${self.name}"#,
                     r#"A braced expression. One line, and a } in running text closes an enclosing block, so write \} for a literal one."#),
        new VocabRow("$$", "$$",
                     r#"A literal $ in front of a word. Everywhere else a $ that is not followed by an identifier, ( or { is already text."#),
    ]
}

/// Every attribute-name prefix that means something.
///
/// An allowlist of two, not "any prefix that is not ours": a mistyped
/// `bnd:value` stays an error instead of becoming an attribute literally called
/// `bnd:value` (`widgets.b`, `is_xml_namespace`).
pub fn namespaces() -> List<VocabRow> {
    return [
        new VocabRow("on:", r#"on:<event>={fn(e: <EventType>) { ... }}"#,
                     "An event handler. The event must be one cortado raises; see events. Every handler takes a UiEvent."),
        new VocabRow("bind:", r#"bind:value={<place>} | bind:checked={<place>}"#,
                     "A two-way binding. It emits the value and the handler that writes it back, which is the pair you would otherwise write yourself."),
    ]
}

/// `bind:` targets and the conversions `bind:value` accepts.
pub fn bindings() -> List<VocabRow> {
    return [
        new VocabRow("bind:value", "<TextField>",
                     "The place is shown as the control's text and written back when the field commits, so the element may then have no children of its own."),
        new VocabRow("bind:checked", "<CheckBox>",
                     "flag(checked) out, and the change handler back."),
    ]
}

/// The `.suffix` conversions on `bind:value`.
///
/// None yet. A control's value arrives as text and is written back as text; a
/// numeric field is a `TextField` the author parses, or — when there is one —
/// a control whose value really is a number. Adding a conversion means
/// deciding what an unparseable value does, and the only answer worth
/// shipping is "leave the field alone", which is a behaviour to design rather
/// than a suffix to list.
pub fn conversions() -> List<string> {
    return []
}

/// Attribute names the framework reads rather than the control.
///
/// Exactly the names `is_reserved_attribute` answers yes to, which is what
/// `Parser.classify` routes on — so an editor can never offer one the compiler
/// does not handle, or miss one it does.
pub fn reserved_attributes() -> List<VocabRow> {
    return [
        new VocabRow("key", r#"key={<expr>}"#,
                     "The identity of this element among its siblings, across renders. A keyed element keeps its control when the list around it is reordered or filtered; without one, siblings match by position. It also names the control for Stage.control(key) and Stage.widget(key) in on_mount."),
        new VocabRow("ref", r#"ref={<place>}"#,
                     "On a component tag only: the instance the tag built, assigned to a place of type Option<T> once the tag is fully configured. A control has no instance to hand back — name it with key= instead."),
    ]
}

// ------------------------------------------------------------ control facts
//
// Each list below mirrors a predicate in `widgets.b`, and the gate asks the
// predicate about every name here and about a corpus of names that must answer
// no. Neither list may grow without the other.

/// The controls markup can name. Everything else that is capitalised is taken
/// to be a component.
pub fn controls() -> List<string> {
    return widget_tags()
}

/// Attributes that are true by being there: `<CheckBox checked />`.
///
/// Exactly the names `is_boolean_attribute` answers yes to, and
/// `tools/check_vocabulary.sh` is what keeps it that way. It was four names for
/// a long time while the compiler had seven: `indeterminate`, `open` and
/// `animating` arrived with the progress bar, the disclosure and the spinner
/// and never reached this list, so every editor reading it believed
/// `<ProgressBar indeterminate />` needed a value. Nothing said so, because
/// nothing compared the two.
pub fn boolean_attributes() -> List<string> {
    return ["animating", "checked", "editable", "enabled", "hidden",
            "indeterminate", "open", "wrap"]
}

/// Every attribute, with the kind of value it takes.
///
/// The kind is what the emitter turns into a `Builder` call, so an editor
/// showing `spacing — number` is showing the same fact the compiler acts on.
pub fn attributes() -> List<VocabRow> {
    let out: List<VocabRow> = []
    for name: string in attribute_names() {
        out.push(new VocabRow(name, attribute_call(name), attribute_note(name)))
    }
    return move out
}

fn attribute_note(name: string) -> string {
    if name == "text" { return "the text this control shows" }
    if name == "spacing" { return "the gap between a container's children" }
    if name == "line_spacing" { return "the gap between one line of a wrapping run and the next" }
    if name == "padding" { return "space kept inside a container, on all four edges" }
    if name == "padding_x" { return "padding on the left and right edges only; later attributes win, edge by edge" }
    if name == "padding_y" { return "padding on the top and bottom edges only; later attributes win, edge by edge" }
    if name == "padding_top" { return "padding on the top edge only" }
    if name == "padding_right" { return "padding on the right edge only" }
    if name == "padding_bottom" { return "padding on the bottom edge only" }
    if name == "padding_left" { return "padding on the left edge only" }
    if name == "margin" { return "space kept outside this control, on all four edges" }
    if name == "margin_x" { return "margin on the left and right edges only; later attributes win, edge by edge" }
    if name == "margin_y" { return "margin on the top and bottom edges only; later attributes win, edge by edge" }
    if name == "margin_top" { return "margin on the top edge only" }
    if name == "margin_right" { return "margin on the right edge only" }
    if name == "margin_bottom" { return "margin on the bottom edge only" }
    if name == "margin_left" { return "margin on the left edge only" }
    if name == "grow" { return "share of leftover space along the main axis" }
    if name == "flex" { return "grow by this share, shrink to fit and start from nothing: grow, shrink and basis in one" }
    if name == "wrap" { return "a stack that starts a new line when the next child would not fit" }
    if name == "shrink" { return "share of overflow this control gives up" }
    if name == "basis" { return "main-axis size to grow or shrink from" }
    if name == "width" { return "pins the width: min_width and max_width at once" }
    if name == "height" { return "pins the height: min_height and max_height at once" }
    if name == "width_percent" { return "the width as a share, 0 to 100, of the room its container offers, less its own margin" }
    if name == "height_percent" { return "the height as a share, 0 to 100, of the room its container offers, less its own margin" }
    if name == "aspect_ratio" { return "width over height, above 0, resolved from whichever axis is settled" }
    if name == "right" { return "inset from a <Box>'s right edge; with x as well, the width stretches between them" }
    if name == "bottom" { return "inset from a <Box>'s bottom edge; with y as well, the height stretches between them" }
    if name == "align_self" { return "this element's own cross-axis place in its run: start, center, end, stretch" }
    if name == "hide_below" { return "shown only while the box around it is at least this wide; hidden takes no room" }
    if name == "hide_above" { return "shown only while the box around it is under this width; hidden takes no room" }
    if name == "min_width" { return "the least width this control takes, in points" }
    if name == "max_width" { return "the most width this control takes, in points" }
    if name == "min_height" { return "the least height this control takes, in points" }
    if name == "max_height" { return "the most height this control takes, in points" }
    if name == "align" { return "cross-axis placement: start, center, end, stretch" }
    if name == "justify" { return "main-axis distribution: start, center, end, space_between, space_around, space_evenly" }
    if name == "enabled" { return "whether the control responds" }
    if name == "hidden" { return "whether the control is drawn; hidden takes no room in the layout" }
    if name == "lines" { return "how many lines a label may wrap onto: 0 for as many as it needs, 1 for one cut short" }
    if name == "checked" { return "a check box's state" }
    if name == "editable" { return "whether a field accepts typing" }
    if name == "columns" { return "a grid's columns, as points, shares like 1fr, or auto" }
    if name == "min_column" { return "the narrowest a grid column may be, so the count follows the room" }
    if name == "max_column" { return "the widest a share of the room may make a grid column" }
    if name == "column_gap" { return "the gap between a grid's columns" }
    if name == "row_gap" { return "the gap between a grid's rows" }
    if name == "font_size" { return "text size in points" }
    if name == "font_role" { return "text size by the job it does: body, heading or caption, at the platform's own size" }
    if name == "value" { return "a slider or progress value" }
    if name == "min" { return "the low end of a range" }
    if name == "max" { return "the high end of a range" }
    if name == "opacity" { return "how opaque this control is, 0.0 to 1.0" }
    if name == "alignment" { return "text alignment inside the control" }
    if name == "step" { return "the increment a slider's thumb lands on; 0 for continuous" }
    if name == "selected" { return "which item of a list is chosen, as an index; -1 for none" }
    if name == "indeterminate" { return "a progress bar with no known total" }
    if name == "day" { return "the day a date picker shows, in seconds since 1970-01-01 UTC" }
    if name == "color" { return "a colour well's colour, written #rgb, #rrggbb or #rrggbbaa" }
    if name == "open" { return "whether a disclosure is showing what is under it" }
    if name == "animating" { return "whether a spinner is turning" }
    if name == "background" { return "the colour behind this control, written #rgb, #rrggbb or #rrggbbaa; refused on the four bezelled text controls" }
    if name == "corner_radius" { return "how far the corners are rounded, in points" }
    if name == "border_width" { return "how thick the outline is, in points, drawn inside the bounds" }
    if name == "border_color" { return "the outline's colour, written #rgb, #rrggbb or #rrggbbaa" }
    if name == "text_color" { return "the colour of the control's own text, written #rgb, #rrggbb or #rrggbbaa; carried by a label and the four controls you type into" }
    if name == "x" { return "how far from the left of a <Box> this control is placed, in points" }
    if name == "y" { return "how far from the top of a <Box> this control is placed, in points" }
    return ""
}

// ------------------------------------------------------------------ printing

/// One JSON string, with the four escapes JSON requires and a `\u00XX` for
/// every other control byte.
pub fn json_string(value: string) -> string {
    let parts: List<string> = []
    parts.push("\"")
    var i: int = 0
    for i < value.len() {
        let b: int = value.byte_at(i) as int
        if b == 34 { parts.push("\\\"") }
        else if b == 92 { parts.push("\\\\") }
        else if b == 10 { parts.push("\\n") }
        else if b == 13 { parts.push("\\r") }
        else if b == 9 { parts.push("\\t") }
        else if b < 32 { parts.push("\\u00{hex_byte(b)}") }
        else { parts.push(value.slice(i, i + 1)) }
        i = i + 1
    }
    parts.push("\"")
    return parts.join("")
}

fn json_strings(values: List<string>) -> string {
    let parts: List<string> = []
    for value: string in values { parts.push(json_string(value)) }
    return "[{parts.join(", ")}]"
}

fn json_rows(rows: List<VocabRow>) -> List<string> {
    let out: List<string> = []
    for row: VocabRow in rows {
        out.push("\{\"name\": {json_string(row.name)}, \"detail\": {json_string(row.detail)}, \"note\": {json_string(row.note)}\}")
    }
    return move out
}

/// Every event, with the class its handler takes and the Builder method it
/// becomes — read out of `events.b`, not restated.
fn json_events() -> List<string> {
    let out: List<string> = []
    for name: string in event_names() {
        out.push("\{\"event\": {json_string(name)}, \"family\": {json_string(event_family(name))}\}")
    }
    return move out
}

fn block_of(name: string, rows: List<string>) -> string {
    if rows.is_empty() { return "  {json_string(name)}: []" }
    return "  {json_string(name)}: [\n    {rows.join(",\n    ")}\n  ]"
}

fn line_of(name: string, value: string) -> string {
    return "  {json_string(name)}: {value}"
}

/// The whole vocabulary as JSON, ending in a newline.
///
/// Shaped by hand rather than by a generic writer: an array of names reads on
/// one line and an array of objects reads one per line, which is what the file
/// this replaces did and what a reviewer of a diff needs.
pub fn vocabulary_json() -> string {
    let lines: List<string> = []
    lines.push(line_of("$generated",
        json_string("Written by `cortado-bx vocabulary`, out of cortado's own tables. Do not edit by hand.")))
    lines.push(line_of("$source", json_string("cortado bx/vocabulary.b, bx/events.b, bx/widgets.b, bx/parse.b")))
    lines.push(line_of("$language", json_string("cortado markup — a whole-file document, not Beans with tags in it: outside <beans> every < opens a tag. Tags name native controls, never HTML elements")))
    lines.push(block_of("blocks", json_rows(blocks())))
    lines.push(block_of("interpolations", json_rows(interpolations())))
    lines.push(block_of("namespaces", json_rows(namespaces())))
    lines.push(block_of("events", json_events()))
    lines.push(block_of("bindings", json_rows(bindings())))
    lines.push(line_of("conversions", json_strings(conversions())))
    lines.push(block_of("reservedAttributes", json_rows(reserved_attributes())))
    lines.push(line_of("controls", json_strings(controls())))
    lines.push(block_of("attributes", json_rows(attributes())))
    lines.push(line_of("booleanAttributes", json_strings(boolean_attributes())))
    return "\{\n{lines.join(",\n")}\n\}\n"
}
