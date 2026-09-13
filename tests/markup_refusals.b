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

fn main() {
    lexing()
    html_documents()
    attribute_bags()
    references()
    slots()
    wrong_control()
}
