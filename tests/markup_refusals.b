// What `.bx` markup refuses, and what it accepts instead.
//
// cortado's markup grew out of latte's, which describes an HTML **document**,
// and a good deal of that language has no meaning over a tree of native
// controls. This file is where each of those forms is held to a refusal that
// talks about the author's program — rather than being quietly accepted and
// failing later, somewhere else, in words about cortado's own insides.
//
// There are three ways that goes wrong, and one case here for each:
//
//   * **A `Builder` call that does not exist.** `<!DOCTYPE>` and `$html`
//     compiled to `b.constant(...)` and `b.raw(...)`, which `Builder` has not
//     got, so the refusal arrived from *beansc*, naming a method of cortado's
//     in a file the author never opened. They are refused in the parser now.
//   * **A field the author never wrote.** `attrs=` and `preserve` on a
//     component tag became `c.attrs = ...`, so beansc said the author's own
//     class has no such field. They are refused by name.
//   * **A form with a full implementation and no way in.** `ref=` was emitted,
//     documented and unreachable: nothing in the parser ever built one. It is
//     wired up here, on component tags, and refused by name on a control.
//
// Every assertion is on the **message**, not only on the refusal. Several of
// these produce a refusal either way — `attrs` on a control was already
// refused as an unknown attribute — and the whole value of the change is which
// sentence the author reads, so a test that only counted refusals would pass
// with the change reverted.
//
// This runs anywhere: `cortado.bx` is pure Beans over `std.fs` and links no
// platform host, which is what lets a markup compiler run on a machine with no
// cortado host at all.
package main

import cortado.bx
import std.io

/// One `.bx` file, out of a markup half and the fields its `<beans>` block
/// declares.
///
/// The class is `Probe` because the file is `probe.bx`: cortado-bx names the
/// class after the file and refuses a block that declares any other. No
/// `package` line, so the folder decides and `Options` says which.
fn probe(markup: List<string>, fields: List<string>) -> bx.Compiled {
    let parts: List<string> = []
    for line: string in markup { parts.push(line) }
    parts.push("<beans>")
    parts.push("pub partial class Probe extends Component \{")
    for line: string in fields { parts.push(line) }
    parts.push("    pub fn init() \{ super.init() \}")
    parts.push("\}")
    parts.push("</beans>")
    var options: bx.Options = new bx.Options()
    options.package_name = "probe"
    options.source_label = "probe.bx"
    return bx.compile_source(parts.join("\n"), "probe.bx", options)
}

/// The same, for markup that needs no fields.
fn markup(lines: List<string>) -> bx.Compiled {
    let none_at_all: List<string> = []
    return probe(lines, none_at_all)
}

/// Whether a refusal *names the right mistake*, and not merely that it
/// refused.
///
/// `tests/shader.b` established this shape and the reason holds here twice
/// over: an unknown attribute and a refused one are both refusals, and the
/// only difference between them is the sentence the author reads.
fn refuses(what: string, out: bx.Compiled, clue: string) {
    if out.is_ok() {
        io.println("  {what} was allowed, and should not have been")
        return
    }
    let said: string = out.report("probe.bx")
    io.println("  {what} refused, saying so: {said.contains(clue)}")
}

/// Whether something compiled, and emitted the call it should have.
fn emits(what: string, out: bx.Compiled, clue: string) {
    if !out.is_ok() {
        io.println("  {what} was refused: {out.report("probe.bx")}")
        return
    }
    io.println("  {what} compiled, emitting it: {out.source.contains(clue)}")
}

/// Whether something compiled and emitted **nothing** matching `clue`.
fn emits_nothing(what: string, out: bx.Compiled, clue: string) {
    if !out.is_ok() {
        io.println("  {what} was refused: {out.report("probe.bx")}")
        return
    }
    io.println("  {what} compiled, writing nothing: {!out.source.contains(clue)}")
}

/// Whether `first` is written before `second` in the generated file.
fn writes_in_order(what: string, out: bx.Compiled, first: string, second: string) {
    if !out.is_ok() {
        io.println("  {what} was refused: {out.report("probe.bx")}")
        return
    }
    match out.source.find(first) {
        none => { io.println("  {what}: {first} was never written") }
        some(early) => {
            match out.source.find(second) {
                none => { io.println("  {what}: {second} was never written") }
                some(late) => { io.println("  {what}: {late > early}") }
            }
        }
    }
}

fn html_documents() {
    io.println("-- markup about an HTML document --")
    refuses("<!DOCTYPE html>",
            markup([r#"<!DOCTYPE html>"#, r#"<Label text="hi" />"#]),
            "declares the grammar of an HTML document")
    refuses("<!ENTITY ...>",
            markup([r#"<!ENTITY nbsp "&#160;">"#, r#"<Label text="hi" />"#]),
            "only <!-- comments --> may start with <!")
    refuses("$html(...)",
            markup([r#"<VStack>"#, r#"  $html(self.rendered)"#, r#"</VStack>"#]),
            "cortado draws native controls, so there is nothing for it to write into")
    // A comment is the one thing that may start with `<!`, and it is a note to
    // whoever reads the `.bx` file: there is nowhere in a control tree to
    // write a remark, so it reaches the generated file as nothing at all.
    emits_nothing("<!-- a note -->",
                  markup([r#"<VStack>"#, r#"  <!-- a note -->"#, r#"  <Label text="hi" />"#, r#"</VStack>"#]),
                  "a note")
}

fn attribute_bags() {
    io.println("-- attributes an HTML element has and a control has not --")
    // Both tag kinds, because both can be written and both are the same
    // mistake. On a control this was already refused — as an unknown attribute,
    // with a spelling suggestion — which sent the author looking for a typo.
    refuses("attrs= on a control",
            markup([r#"<VStack attrs={self.extra}>"#, r#"  <Label text="hi" />"#, r#"</VStack>"#]),
            "there is no bag here and nothing to spread into")
    refuses("attrs= on a component",
            markup([r#"<Hint attrs={self.extra} />"#]),
            "there is no bag here and nothing to spread into")
    refuses("preserve on a control",
            markup([r#"<VStack preserve>"#, r#"  <Label text="hi" />"#, r#"</VStack>"#]),
            "preserve keeps a subtree out of the diff")
    refuses("preserve on a component",
            markup([r#"<Hint preserve />"#]),
            "preserve keeps a subtree out of the diff")
    // What reserving the two names costs, said out loud: a component whose own
    // field is called `attrs` cannot have it set from markup either. That is
    // the price of answering the question the author actually asked, and it is
    // charged on these two names and no others.
    refuses("a component parameter that happens to be called attrs",
            probe([r#"<Hint attrs="two" />"#], [r#"    pub attrs: string = """#]),
            "there is no bag here and nothing to spread into")
}

fn references() {
    io.println("-- ref= --")
    emits("ref= on a component tag",
          probe([r#"<Hint ref={self.hint} />"#], [r#"    pub hint: Option<Hint> = none"#]),
          "self.hint = some(_cortado_c)")
    // Last, after every parameter, so the parent's field is published only once
    // the child is completely configured — and so the same markup does not mean
    // two things depending on the order the attributes were written in.
    writes_in_order("ref= is written after the parameters",
                    probe([r#"<Hint ref={self.hint} note="hi" />"#],
                          [r#"    pub hint: Option<Hint> = none"#]),
                    r#"_cortado_c.note = "hi""#, "self.hint = some(_cortado_c)")
    refuses("ref= on a control",
            probe([r#"<Label ref={self.field} text="hi" />"#], [r#"    pub field: Option<int> = none"#]),
            "Stage.control(key) for its handle, Stage.widget(key) for the control itself")
    refuses("ref with no place to put the child",
            markup([r#"<Hint ref />"#]),
            "ref needs somewhere to put the child")
    // `key=` goes through the same reserved-attribute routing as `ref=`, so its
    // own refusal is checked here: a change to one must not lose the other.
    refuses("key= with a literal rather than an expression",
            markup([r#"<Label key="row" text="hi" />"#]),
            "key needs an expression")
    emits("key= with an expression",
          markup([r#"<Label key={self.id} text="hi" />"#]),
          r#"b.key("{self.id}")"#)
    refuses("key= on a component tag",
            markup([r#"<Hint key={self.id} />"#]),
            "it belongs on a tag directly inside a $for body")
}

fn slots() {
    io.println("-- $slot --")
    // The three placing forms. Each is one `fragment` call, and the number in
    // it is the placement site — which is what makes two placements of one
    // template two children rather than one.
    emits("$slot", markup([r#"<VStack>"#, r#"  $slot"#, r#"</VStack>"#]),
          "b.fragment(\"0\", self.body)")
    emits("$slot(<expr>)", markup([r#"<VStack>"#, r#"  $slot(self.extra)"#, r#"</VStack>"#]),
          "b.fragment(\"0\", self.extra)")
    emits("$slot:<name>", markup([r#"<VStack>"#, r#"  $slot:row"#, r#"</VStack>"#]),
          "b.fragment(\"0\", self.row)")
    emits("$slot:<name> as <expr>",
          markup([r#"<VStack>"#, r#"  $slot:row as self.item"#, r#"</VStack>"#]),
          "b.fragment(\"0\", fn(_cortado_inner: Builder) \{ self.row(_cortado_inner, self.item) \})")
    // Two placements of one template take two sites, which is the whole point
    // of the site: `Builder.fragment` keys everything the body writes by it, so
    // the two produce two independent children.
    let twice: bx.Compiled = markup([r#"<VStack>"#, r#"  $slot"#, r#"  $slot"#, r#"</VStack>"#])
    emits("the first of two placements", twice, "b.fragment(\"0\", self.body)")
    emits("the second of two placements", twice, "b.fragment(\"1\", self.body)")
    // And a placement inside a $for carries the row, because one emitted call
    // runs once per turn — the number in it is the same every time, so without
    // the row every row of a table would place its cell template under one
    // site. A component tag in a loop has carried the row from the start; this
    // is the same identity, written by the same helper.
    emits("a placement inside a $for",
          markup([r#"<VStack>"#, r#"  $for row: Row in self.rows {"#, r#"    $slot:cell as row"#,
                  r#"  }"#, r#"</VStack>"#]),
          "b.fragment(\"0.\{_cortado_row_0\}\", fn(_cortado_inner: Builder) \{ self.cell(_cortado_inner, row) \})")
    emits("a component tag inside a $for, for comparison",
          markup([r#"<VStack>"#, r#"  $for row: Row in self.rows {"#, r#"    <Hint text={row.title} />"#,
                  r#"  }"#, r#"</VStack>"#]),
          "b.child<Hint>(\"c0.\{_cortado_row_0\}\"")
    // Defining one. Only as a direct child of a component tag, because that is
    // the only place a template has anything to be handed to.
    emits("a template defined on a component tag",
          markup([r#"<Card>"#, r#"  $slot:row as r: Row { <Label text={r.title} /> }"#, r#"</Card>"#]),
          "_cortado_c.row = fn(_cortado_inner: Builder, r: Row) \{")
    emits("a template with no parameter",
          markup([r#"<Card>"#, r#"  $slot:cap { <Label text="a caption" /> }"#, r#"</Card>"#]),
          "_cortado_c.cap = fn(_cortado_inner: Builder) \{")
    emits("a component tag's children become its body",
          markup([r#"<Card>"#, r#"  <Label text="hi" />"#, r#"</Card>"#]),
          "_cortado_c.body = fn(_cortado_inner: Builder) \{")
    refuses("a template defined outside a component tag",
            markup([r#"<VStack>"#, r#"  $slot:row as r: Row { <Label text={r.title} /> }"#, r#"</VStack>"#]),
            "supplies a template and only reads that way inside a component tag")
}

/// What the scanners must not mistake for something else.
///
/// `bx/lex.b` claims a stack that keeps raw strings, nested block comments and
/// interpolation apart; before these cases, nothing held it to that. A walker
/// that got any one of them wrong finds the end of an attribute in the wrong
/// place, and the generated file is then wrong in a way the author never wrote.
fn lexing() {
    io.println("-- what the scanners must not mistake --")
    // A raw string opens no interpolation, so `{id}` inside one is four
    // unremarkable bytes and not the end of the attribute. crema's older
    // walker mis-scanned exactly this.
    emits("braces inside a raw string",
          markup([r#"<Label text={r"/users/{id}"} />"#]),
          r#"/users/{id}"#)
    // An ordinary string's braces *are* interpolation, and must survive into
    // the generated file as interpolation.
    emits("braces inside an ordinary string",
          markup([r#"<Label text={"hello {self.name}"} />"#]),
          r#"{self.name}"#)
    // A brace inside a comment is not a brace the scanner may count.
    emits("a brace inside a line comment",
          markup([r#"<VStack>"#,
                  r#"  ${ // a } that closes nothing"#,
                  r#"     let _: int = 1 }"#,
                  r#"</VStack>"#]),
          "let _: int = 1")
    // Block comments nest in Beans, so the first `*/` does not end the outer
    // one. A scanner that stopped there would read code as prose.
    emits("a nested block comment",
          markup([r#"<VStack>"#,
                  r#"  ${ /* outer /* inner */ still the comment */"#,
                  r#"     let kept: int = 7 }"#,
                  r#"</VStack>"#]),
          "let kept: int = 7")
    // A quote inside a comment closes no string.
    emits("a quote inside a comment",
          markup([r#"<VStack>"#,
                  r#"  ${ /* it's fine */ let ok: int = 2 }"#,
                  r#"</VStack>"#]),
          "let ok: int = 2")
}

/// An attribute that is real, spelled right, and on the wrong control.
///
/// Until there was a per-kind table this compiled: the emitter never saw the
/// tag, so the property went onto the wrong control and did nothing.
fn wrong_control() {
    io.println("-- an attribute the control has not got --")
    // The three the plan named, one per value shape: a flag, a number and a
    // word.
    refuses("checked on a label", markup([r#"<Label checked />"#]),
            "<Label> has no checked")
    refuses("a day on a separator", markup([r#"<Separator day={0} />"#]),
            "<Separator> has no day")
    refuses("open on a button", markup([r#"<Button open />"#]),
            "<Button> has no open")
    // `r##"…"##` because the value itself contains `"#`, which would end an
    // `r#"…"#` in the middle of the colour.
    refuses("a colour on a text field", markup([r##"<TextField color="#ff8800" />"##]),
            "<TextField> has no color")
    // A font size on a container: the one every host answered differently,
    // because GTK4 and Win32 will style any widget and the two Apple hosts
    // will not.
    refuses("a font size on a container", markup([r#"<VStack font_size={13} />"#]),
            "<VStack> has no font_size")

    // The refusal says where the attribute does belong, from the same table.
    refuses("and it says which controls do carry it", markup([r#"<Label checked />"#]),
            "carried by CheckBox, RadioButton, Switch")

    // A misspelling is still a misspelling, and not the same mistake.
    refuses("a misspelling is still a misspelling", markup([r#"<Label chekced />"#]),
            "did you mean checked")

    // And the same attribute on a control that does carry it compiles.
    emits("checked on a check box", markup([r#"<CheckBox checked />"#]),
          r#"flag("checked", true)"#)
    emits("a font size on a label", markup([r#"<Label font_size={13} />"#]),
          r#"number("font_size"#)
    // A layout name belongs to no control, so no per-kind rule refuses one.
    emits("spacing on a label", markup([r#"<Label spacing={4} />"#]),
          r#"number("spacing"#)
}

/// Dressing a control from markup.
///
/// The four layer keys reach `.bx` the way every other property does. A colour
/// is a word here and a packed integer by the time it reaches the ABI.
fn dressing() {
    io.println("-- dressing a control in markup --")
    emits("a background on a button", markup([r##"<Button background="#ff8800" />"##]),
          r##"word("background", "#ff8800")"##)
    emits("a corner radius", markup([r#"<Button corner_radius={6} />"#]),
          r#"number("corner_radius"#)
    emits("a border", markup([r##"<VStack border_width={1} border_color="#00000030" />"##]),
          r##"word("border_color", "#00000030")"##)
    // The one control the rule refuses, refused where it is written rather
    // than at run time.
    refuses("a background on a text field", markup([r##"<TextField background="#ff8800" />"##]),
            "<TextField> has no background")
    // Corners and borders have no per-kind rule, so the same field takes both.
    emits("but the same field takes a corner radius",
          markup([r#"<TextField corner_radius={4} />"#]),
          r#"number("corner_radius"#)
    // A value that is the wrong *shape* is the Builder's to refuse, uniformly:
    // `align="nonsense"` compiles here too. One parser for a colour, not two.
    emits("a colour that is not one still compiles",
          markup([r##"<Button background="#gg0000" />"##]),
          r##"word("background", "#gg0000")"##)

    // A colour a field decides. This was refused as "a fixed set of words"
    // until the word branch stopped treating a colour as a closed vocabulary.
    emits("a background a field decides",
          probe([r#"<Button background={self.tint} />"#],
                [r##"    pub tint: string = "#3b6ea5""##]),
          r#"word("background", self.tint)"#)
    emits("a swatch colour a field decides",
          probe([r#"<ColorWell color={self.ink} />"#],
                [r##"    pub ink: string = "#101010""##]),
          r#"word("color", self.ink)"#)
    emits("a border colour a field decides",
          probe([r#"<VStack border_color={self.edge} />"#],
                [r##"    pub edge: string = "#00000030""##]),
          r#"word("border_color", self.edge)"#)

    // And the half that is a closed set still needs its literal, which is the
    // whole reason the branch exists.
    refuses("align still needs a literal",
            probe([r#"<VStack align={self.mode} />"#],
                  [r#"    pub mode: string = "center""#]),
            "align takes one of a fixed set of words")
    refuses("and so does justify",
            probe([r#"<VStack justify={self.mode} />"#],
                  [r#"    pub mode: string = "center""#]),
            "justify takes one of a fixed set of words")
    // The example in that refusal is the attribute's own word, or it sends
    // somebody to write font_role="center".
    refuses("and font_role, with its own set in the example",
            probe([r#"<Label font_role={self.role} text="hi" />"#],
                  [r#"    pub role: string = "body""#]),
            r#"font_role takes one of a fixed set of words, so it needs a literal: font_role="body""#)
    emits("a font role by name",
          markup([r#"<Label font_role="heading" text="Petrichor" />"#]),
          r#"b.word("font_role", "heading")"#)
}

/// A scroll view holds one content view on every platform here.
fn scrolling() {
    io.println("-- what a scroll view scrolls --")
    refuses("two children in a scroll view",
            markup([r#"<ScrollView>"#,
                    r#"  <Label text="one" />"#,
                    r#"  <Label text="two" />"#,
                    r#"</ScrollView>"#]),
            "<ScrollView> holds 2 children, and a scroll view scrolls one")
    emits("one is what it takes",
          markup([r#"<ScrollView>"#,
                  r#"  <VStack><Label text="one" /><Label text="two" /></VStack>"#,
                  r#"</ScrollView>"#]),
          r#"open("ScrollView")"#)
    // The refusal is about the tag, not about holding children: the same two
    // labels in the box beside it are fine.
    emits("and a plain container still holds as many as it likes",
          markup([r#"<VStack><Label text="one" /><Label text="two" /></VStack>"#]),
          r#"open("VStack")"#)
}

fn insets() {
    io.println("-- padding and margin, one edge at a time --")
    // Each per-edge name is a `number` call like the bare one; the merge is
    // the Builder's, so all the compiler has to do is pass the name through.
    emits("padding_x on a container",
          markup([r#"<VStack padding_x={16}><Label text="hi" /></VStack>"#]),
          r#"number("padding_x", (16) as f64)"#)
    emits("padding_top beside padding",
          markup([r#"<VStack padding={8} padding_top={20}><Label text="hi" /></VStack>"#]),
          r#"number("padding_top", (20) as f64)"#)
    writes_in_order("and in the order they were written",
                    markup([r#"<VStack padding={8} padding_top={20}><Label text="hi" /></VStack>"#]),
                    r#"number("padding", (8) as f64)"#,
                    r#"number("padding_top", (20) as f64)"#)
    emits("margin_left on a control",
          markup([r#"<HStack><Label margin_left={5} text="hi" /></HStack>"#]),
          r#"number("margin_left", (5) as f64)"#)
    emits("margin_y from an expression",
          markup([r#"<HStack><Label margin_y={self.gap} text="hi" /></HStack>"#]),
          r#"number("margin_y", (self.gap) as f64)"#)
    // The names are closed: the old spelling of an edge is a spelling
    // mistake, and the refusal offers the one that exists.
    refuses("padding_horizontal",
            markup([r#"<VStack padding_horizontal={16}><Label text="hi" /></VStack>"#]),
            "padding_x")
    refuses("marginTop",
            markup([r#"<HStack><Label marginTop={4} text="hi" /></HStack>"#]),
            "margin_top")
}

fn placements() {
    io.println("-- what a component tag carries --")
    // A placement is the parent's to write, so it rides the call that shows
    // the child rather than the setup closure that sets its fields.
    emits("margin_left on a component tag",
          markup([r#"<VStack><Tile margin_left={8} /></VStack>"#]),
          r#"}).number("margin_left", (8) as f64)"#)
    emits("a parameter beside it is still the component's field",
          markup([r#"<VStack><Tile title="x" grow={1} /></VStack>"#]),
          r#"c.title = "x""#)
    emits("and every placement rides the one call",
          markup([r#"<VStack><Tile grow={1} align="center" /></VStack>"#]),
          r#"}).number("grow", (1) as f64).word("align", "center")"#)
    emits("a placement from an expression",
          markup([r#"<Box><Tile x={self.left} /></Box>"#]),
          r#"}).number("x", (self.left) as f64)"#)
    emits("the far edge of a box",
          markup([r#"<Box><Tile right={0} bottom={12} /></Box>"#]),
          r#"}).number("right", (0) as f64).number("bottom", (12) as f64)"#)
    emits("a component's own place in its run",
          markup([r#"<HStack><Tile align_self="center" /></HStack>"#]),
          r#"}).word("align_self", "center")"#)
    // `padding` is the component's own: a field it may forward to its root.
    emits("padding on a component tag is its parameter",
          markup([r#"<VStack><Tile padding={8} /></VStack>"#]),
          "c.padding = 8")
    refuses("a placement with no value",
            markup([r#"<VStack><Tile grow /></VStack>"#]),
            "needs a value")
    refuses("align from an expression",
            markup([r#"<VStack><Tile align={self.mode} /></VStack>"#]),
            "needs a literal")
}

fn bounds() {
    io.println("-- one size bound at a time --")
    emits("max_width on a control",
          markup([r#"<VStack><Label max_width={200} text="hi" /></VStack>"#]),
          r#"number("max_width", (200) as f64)"#)
    emits("min_height on a component tag",
          markup([r#"<VStack><Tile min_height={20} /></VStack>"#]),
          r#"}).number("min_height", (20) as f64)"#)
    emits("width_percent on a control",
          markup([r#"<VStack><Label width_percent={50} text="hi" /></VStack>"#]),
          r#"number("width_percent", (50) as f64)"#)
    emits("aspect_ratio on a component tag",
          markup([r#"<VStack><Tile aspect_ratio={1.5} /></VStack>"#]),
          r#"}).number("aspect_ratio", (1.5) as f64)"#)
    // Hidden by the box around it: the layout's decision, in one attribute.
    emits("hide_below on a control",
          markup([r#"<VStack><Label hide_below={500} text="side" /></VStack>"#]),
          r#"number("hide_below", (500) as f64)"#)
    emits("hide_above on a component tag",
          markup([r#"<VStack><Tile hide_above={900} /></VStack>"#]),
          r#"}).number("hide_above", (900) as f64)"#)
    // The window's size is a plain method call, so a breakpoint is a `$if`.
    emits("a breakpoint on the viewport",
          markup([r#"<VStack>"#, r#"  $if self.viewport().width < 600 { <Label text="narrow" /> }"#, r#"</VStack>"#]),
          "if self.viewport().width < 600")
    refuses("maxWidth",
            markup([r#"<VStack><Label maxWidth={200} text="hi" /></VStack>"#]),
            "max_width")
}

fn wrapping() {
    io.println("-- a run that wraps --")
    emits("wrap is a stack's own flag",
          markup([r#"<HStack wrap spacing={8} line_spacing={6}><Label text="a" /><Label text="b" /></HStack>"#]),
          r#"flag("wrap", true)"#)
    emits("and line_spacing is one of its numbers",
          markup([r#"<HStack wrap spacing={8} line_spacing={6}><Label text="a" /></HStack>"#]),
          r#"number("line_spacing", (6) as f64)"#)
    emits("flex is one number for three",
          markup([r#"<VStack><Tile flex={1} /></VStack>"#]),
          r#"}).number("flex", (1) as f64)"#)
    // The three families are one: the old tags are refused by name, and the
    // sentence says what to write instead.
    refuses("<HWrap> is retired",
            markup([r#"<HWrap><Label text="a" /></HWrap>"#]),
            "write <HStack wrap>")
    refuses("<VWrap> is retired",
            markup([r#"<VWrap><Label text="a" /></VWrap>"#]),
            "write <VStack wrap>")
    refuses("<VFlex> is retired",
            markup([r#"<VFlex><Label text="a" /></VFlex>"#]),
            "write <VStack>")
    refuses("<HFlex> is retired",
            markup([r#"<HFlex><Label text="a" /></HFlex>"#]),
            "write <HStack>")
}

fn main() {
    lexing()
    html_documents()
    attribute_bags()
    references()
    slots()
    wrong_control()
    dressing()
    scrolling()
    insets()
    placements()
    bounds()
    wrapping()
}
