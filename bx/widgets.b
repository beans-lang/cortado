// widgets.b — the vocabulary cortado markup is written in.
//
// The counterpart of latte's `html.b`, and much smaller for a reason worth
// stating: HTML is a language with a hundred elements, a void-element list, a
// raw-text list, an entity table, a URL scheme allowlist and an escaping
// discipline, because HTML is text that a browser parses. cortado markup names
// **controls**. There is nothing to escape into, no document to inject into,
// and the set of tags is closed — so the only tables here are the ones that
// say what a name means.
//
// **This table and `cortado.component.Vocabulary` are one contract.** That one
// answers at run time, for hand-written components; this one answers at
// compile time, for generated ones. They must agree, and
// `tools/check_vocabulary.sh` fails the build when they do not. Two tables is
// one more than anybody wants, and the reason for it is that this package must
// build on a machine with no host: `cortado.component` reaches
// `cortado.host`'s foreign declarations, and a markup compiler that could only
// be built on macOS would be a markup compiler nobody on Windows could run.

package bx

/// Whether `tag` names a control cortado knows.
///
/// The closed set. Anything else that starts with a capital letter is taken to
/// be a component; anything else that does not is refused by name.
pub fn is_widget_tag(tag: string) -> bool {
    if tag == "VStack" { return true }
    if tag == "HStack" { return true }
    if tag == "VFlex" { return true }
    if tag == "HFlex" { return true }
    if tag == "Grid" { return true }
    if tag == "Box" { return true }
    if tag == "Container" { return true }
    if tag == "Label" { return true }
    if tag == "Button" { return true }
    if tag == "TextField" { return true }
    if tag == "CheckBox" { return true }
    if tag == "Image" { return true }
    if tag == "Slider" { return true }
    if tag == "ProgressBar" { return true }
    if tag == "Separator" { return true }
    if tag == "TextArea" { return true }
    if tag == "ComboBox" { return true }
    if tag == "ScrollView" { return true }
    if tag == "RadioButton" { return true }
    if tag == "Canvas" { return true }
    if tag == "Switch" { return true }
    if tag == "SecureField" { return true }
    if tag == "Stepper" { return true }
    if tag == "LevelIndicator" { return true }
    if tag == "Table" { return true }
    if tag == "SearchField" { return true }
    if tag == "Spinner" { return true }
    if tag == "Link" { return true }
    if tag == "Segmented" { return true }
    if tag == "GroupBox" { return true }
    if tag == "DatePicker" { return true }
    if tag == "ColorWell" { return true }
    if tag == "Disclosure" { return true }
    if tag == "TabView" { return true }
    if tag == "SplitView" { return true }
    return false
}

/// Whether `tag` names another component rather than a control.
///
/// The rule differs from latte's, and it has to. There, an element is
/// lowercase and a component is capitalized, because HTML's own elements are
/// lowercase. Here every control is capitalized too — `<Button>` is a control,
/// `<OrderRow>` is a component — so the test is membership of the closed set
/// above, not spelling.
///
/// The consequence is worth being exact about, because it is a real cost.
/// `<Buton>` is a typo, but cortado-bx cannot know that — it becomes a
/// component tag, and the refusal comes from **beansc**, as
/// `unknown type 'Buton'`, pointing at the *generated* file rather than at the
/// `.bx`. The generated line carries a `// checkout.bx:16` trace comment, so
/// the way back is one line up, but it is a hop the author should not have to
/// make.
///
/// A lowercase tag is refused here, with a suggestion, because a lowercase
/// name can never be a component. Closing the gap for a capitalised one would
/// mean refusing any tag within two edits of a control name, which would also
/// refuse a component somebody legitimately called `Lable`.
pub fn names_a_component(tag: string) -> bool {
    if tag.len() == 0 { return false }
    if is_widget_tag(tag) { return false }
    let first: int = tag.byte_at(0) as int
    return first >= 65 && first <= 90
}

/// An attribute that is true by being there: `<CheckBox checked />`.
pub fn is_boolean_attribute(name: string) -> bool {
    if name == "enabled" { return true }
    if name == "hidden" { return true }
    if name == "checked" { return true }
    if name == "editable" { return true }
    if name == "indeterminate" { return true }
    if name == "open" { return true }
    return false
}

/// The prefixes an attribute may carry before a colon.
///
/// Two, and both mean something: `on:` subscribes to an event, `bind:` binds a
/// control's value to a field in both directions. An unknown prefix is refused
/// rather than passed through as part of the name, because `onclick=` — the
/// prefix left off by mistake — should say so.
pub fn is_xml_namespace(prefix: string) -> bool {
    return prefix == "on" || prefix == "bind"
}

/// An attribute the framework reads, rather than one the control carries.
pub fn is_reserved_attribute(name: string) -> bool {
    return name == "key"
}

/// Which `Builder` method an attribute becomes, or `""` when the name is not
/// one cortado knows.
///
/// This is the whole of the compile-time half of the contract. `text` is the
/// control's own text, `flag` a true/false property, `number` anything
/// measured — a real property or one of the layout numbers — and `word` a
/// named choice out of a fixed set.
pub fn attribute_call(name: string) -> string {
    if name == "text" { return "text" }
    if is_boolean_attribute(name) { return "flag" }
    if name == "min" || name == "max" || name == "value" ||
       name == "font_size" || name == "step" || name == "opacity" ||
       name == "day" {
        return "number"
    }
    if name == "alignment" || name == "selected" { return "number" }
    if name == "spacing" || name == "padding" || name == "margin" ||
       name == "grow" || name == "shrink" || name == "basis" ||
       name == "width" || name == "height" {
        return "number"
    }
    // A colour is a word here — `color="#ff8800"` — and a whole number by the
    // time it reaches the ABI. `Builder.word` is where the one becomes the
    // other, so the hex spelling is parsed in exactly one place and `#abc`
    // means the same thing in markup as it does in a shader.
    if name == "align" || name == "justify" || name == "color" { return "word" }
    return ""
}

/// Every attribute name cortado knows, for a diagnostic that can suggest one.
pub fn attribute_names() -> List<string> {
    return ["align", "alignment", "basis", "checked", "color", "day",
            "editable", "enabled",
            "font_size", "grow", "height", "hidden", "indeterminate",
            "justify", "margin", "max", "min", "opacity", "open", "padding",
            "selected", "shrink", "spacing", "step", "text", "value", "width"]
}

/// Every control tag, for the same reason.
pub fn widget_tags() -> List<string> {
    return ["Box", "Button", "Canvas", "CheckBox", "ColorWell", "ComboBox",
            "Container", "DatePicker", "Disclosure",
            "Grid", "GroupBox", "HFlex", "HStack", "Image", "Label",
            "LevelIndicator", "Link",
            "ProgressBar", "RadioButton", "ScrollView", "SecureField",
            "SearchField", "Segmented", "Separator", "Slider", "Spinner", "SplitView", "Stepper",
            "Switch", "TabView", "Table", "TextArea", "TextField", "VFlex", "VStack"]
}

/// Whether a tag is spelled like an identifier.
///
/// Not a security question here — there is no document to inject into — but a
/// correctness one: a tag becomes a type name or a table lookup in generated
/// Beans, and one that is not an identifier produces a generated file that
/// does not parse, with the error landing on a line the author never wrote.
pub fn tag_name_is_safe(tag: string) -> bool {
    return is_identifier(tag)
}

/// The same, for an attribute name, after any `on:` or `bind:` prefix.
pub fn attribute_name_is_safe(name: string) -> bool {
    return is_identifier(name)
}

fn is_identifier(text: string) -> bool {
    if text.len() == 0 { return false }
    var index: int = 0
    for index < text.len() {
        let b: int = text.byte_at(index) as int
        let letter: bool = (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
        let digit: bool = b >= 48 && b <= 57
        if index == 0 {
            if !letter && b != 95 { return false }
        } else {
            if !letter && !digit && b != 95 { return false }
        }
        index = index + 1
    }
    return true
}

// --------------------------------------------------- embedding in Beans source

/// Escape `value` so it can be written inside a Beans double-quoted string.
///
/// Carried over from latte's `html.b` unchanged, because the job is identical:
/// whatever the markup said has to survive being written into a generated
/// source file. Braces are escaped as well as quotes and backslashes, since a
/// Beans string interpolates.
pub fn escape_beans_string(value: string) -> string {
    let parts: List<string> = []
    var run: int = 0
    var i: int = 0
    for i < value.len() {
        let b: int = value.byte_at(i) as int
        var replacement: string = ""
        if b == 92 { replacement = "\\\\" }
        if b == 34 { replacement = "\\\"" }
        if b == 123 { replacement = "\\\{" }
        if b == 125 { replacement = "\\\}" }
        if b == 10 { replacement = "\\n" }
        if b == 9 { replacement = "\\t" }
        if b == 13 { replacement = "\\r" }
        if b == 0 { replacement = "\\0" }
        if replacement == "" && b < 32 {
            replacement = "\\x{hex_byte(b)}"
        }
        if b == 127 { replacement = "\\x7f" }
        if replacement != "" {
            parts.push(value.slice(run, i))
            parts.push(replacement)
            run = i + 1
        }
        i = i + 1
    }
    if run == 0 { return value }
    parts.push(value.slice(run, value.len()))
    return parts.join("")
}

/// Two lowercase hex digits for a byte.
pub fn hex_byte(value: int) -> string {
    let digits: string = "0123456789abcdef"
    let hi: int = (value / 16) % 16
    let lo: int = value % 16
    return "{digits.slice(hi, hi + 1)}{digits.slice(lo, lo + 1)}"
}

// ------------------------------------------------------------- did you mean?

/// The attribute names, comma-separated, for the body of a diagnostic.
pub fn attribute_list() -> string {
    return attribute_names().join(", ")
}

/// The tag names, comma-separated.
pub fn widget_list() -> string {
    return widget_tags().join(", ")
}

/// The nearest attribute name to `name`, or `""` when nothing is close enough
/// to suggest.
pub fn nearest_attribute(name: string) -> string {
    return nearest_of(name, attribute_names())
}

/// The nearest of `candidates` to `name` within two edits.
///
/// Two, and not more: a suggestion that is wrong sends the reader to fix the
/// wrong thing, which costs more than no suggestion at all.
pub fn nearest_of(name: string, candidates: List<string>) -> string {
    var best: string = ""
    var best_distance: int = 3
    for candidate: string in candidates {
        let distance: int = edit_distance(name, candidate)
        if distance < best_distance {
            best_distance = distance
            best = candidate
        }
    }
    return best
}

/// Levenshtein distance between two short ASCII names.
///
/// Two rows rather than a matrix: the names here are at most eleven bytes and
/// the tables are twenty long, so this runs once per bad name and never on a
/// path anyone measures.
pub fn edit_distance(from: string, to: string) -> int {
    let width: int = to.len() + 1
    var previous: List<int> = []
    var current: List<int> = []
    var i: int = 0
    for i < width {
        previous.push(i)
        current.push(0)
        i = i + 1
    }
    var row: int = 1
    for row <= from.len() {
        current[0] = row
        var column: int = 1
        for column < width {
            var cost: int = 1
            if from.byte_at(row - 1) == to.byte_at(column - 1) { cost = 0 }
            var best: int = previous[column] + 1
            if current[column - 1] + 1 < best { best = current[column - 1] + 1 }
            if previous[column - 1] + cost < best { best = previous[column - 1] + cost }
            current[column] = best
            column = column + 1
        }
        var copy: int = 0
        for copy < width {
            previous[copy] = current[copy]
            copy = copy + 1
        }
        row = row + 1
    }
    return previous[width - 1]
}
