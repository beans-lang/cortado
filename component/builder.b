// What a component renders into.
package component

import cortado.widgets
import cortado.host
import cortado.events
import cortado.layout
import cortado.geometry

/// Collects a render into a tree of `Element`s.
///
/// This is the method ABI the `.bx` markup compiler emits against, and it is
/// deliberately something a person can also write by hand. Markup is sugar
/// over these calls, not a second way of saying the same thing — so a
/// component written by hand and one generated from markup produce identical
/// trees, and the framework has one input to test.
///
/// ```beans
/// pub override fn render(into: component.Builder) {
///     into.open("VStack")
///     into.number("spacing", 12.0)
///         into.open("Label")
///         into.text(self.title)
///         into.close()
///         into.open("Button")
///         into.text("Buy")
///         into.on("click", fn(event: events.UiEvent) { self.buy() })
///         into.close()
///     into.close()
/// }
/// ```
///
/// ### Why nothing here answers `Result`
///
/// A render body is a description, and threading `?` through forty lines of
/// description would bury the description. So mistakes — an unknown tag, a
/// misspelled attribute, a `close` with nothing open — are recorded as faults
/// and `finish()` answers them all at once. The author sees every problem in
/// their markup in one message instead of the first one, and a render that
/// went wrong never reaches the platform.
pub class Builder {
    open_stack: List<Element> = []
    root: Option<Element> = none
    faults: List<string> = []

    /// Who renders child components, when this builder is building a real
    /// mount. `none` when nothing is composing — a builder used to compare two
    /// renders in a test, say — and `child()` then reports it rather than
    /// quietly dropping the child.
    composer: Option<Composer> = none

    /// The prefix every child key is qualified by while a fragment body is
    /// running, or `""` outside every fragment. `fragment` maintains it; see
    /// the note there for why it exists and how it composes with the mount's
    /// own scoping.
    fragment_scope: string = ""

    pub fn init() {}

    /// Framework use: the mount that will render child components.
    pub fn set_composer(who: Composer) {
        self.composer = some(who)
    }

    // ---- structure ----

    /// Opens a widget. Everything set until the matching `close` belongs to
    /// it, and any element opened in between becomes its child.
    pub fn open(tag: string) {
        match Vocabulary.kind_of(tag) {
            none => {
                self.faults.push("<{tag}> is not a widget cortado knows")
                // A placeholder still goes on the stack, so the `close` that
                // follows is not reported as a second, imaginary mistake.
                self.push(new Element(widgets.WidgetKind.container, tag))
            }
            some(kind) => {
                var element: Element = new Element(kind, tag)
                element.arranger = Vocabulary.arranger_of(tag)
                self.push(element)
            }
        }
    }

    /// Gives the element being built an identity that survives reordering.
    pub fn key(value: string) {
        match self.current() {
            none => { self.faults.push("key=\"{value}\" with no element open") }
            some(element) => { element.key = value }
        }
    }

    /// Closes the element being built.
    pub fn close() {
        if self.open_stack.len() == 0 {
            self.faults.push("close with nothing open")
            return
        }
        let finished: Element = self.open_stack.remove(self.open_stack.len() - 1)
        if self.open_stack.len() == 0 {
            match self.root {
                none => { self.root = some(finished) }
                some(already) => {
                    self.faults.push("a render has two roots: <{already.tag}> and <{finished.tag}>")
                }
            }
            return
        }
        self.open_stack[self.open_stack.len() - 1].add(finished)
    }

    // ---- values ----

    /// The text this control shows.
    pub fn text(value: string) {
        match self.current() {
            none => { self.faults.push("text with no element open") }
            some(element) => { element.set(Attribute.of_text(value)) }
        }
    }

    /// Refuses a property this control has not got, and says which do.
    /// `true` when refused. One spelling for three call sites.
    fn refuse_unless_carried(element: Element, name: string) -> bool {
        if Vocabulary.carries(element.kind, name) { return false }
        self.faults.push("<{element.tag}> has no {name} — {Vocabulary.who_carries(name)}")
        return true
    }

    /// A true/false property: `enabled`, `hidden`, `checked`, `editable`.
    pub fn flag(name: string, value: bool) {
        match self.current() {
            none => { self.faults.push("{name} with no element open") }
            some(element) => {
                let property: int = Vocabulary.property_of(name)
                if property < 0 {
                    self.faults.push("<{element.tag}> has no attribute called '{name}'")
                    return
                }
                if self.refuse_unless_carried(element, name) { return }
                element.set(Attribute.of_flag(property, value))
            }
        }
    }

    /// A numeric property, or one of the layout numbers — `spacing`, `padding`,
    /// `grow`, `shrink`, `basis`, `margin`, `width`, `height` and their per-edge forms.
    pub fn number(name: string, value: f64) {
        match self.current() {
            none => { self.faults.push("{name} with no element open") }
            some(element) => {
                if Vocabulary.is_layout_name(name) {
                    self.layout_number(element, name, value)
                    return
                }
                let property: int = Vocabulary.property_of(name)
                if property < 0 {
                    self.faults.push("<{element.tag}> has no attribute called '{name}'")
                    return
                }
                if self.refuse_unless_carried(element, name) { return }
                if Vocabulary.kind_of_property(name) == AttributeKind.real {
                    element.set(Attribute.of_real(property, value))
                } else {
                    element.set(Attribute.of_whole(property, value as int))
                }
            }
        }
    }

    /// A named choice: `align`, `justify`.
    pub fn word(name: string, value: string) {
        match self.current() {
            none => { self.faults.push("{name} with no element open") }
            some(element) => {
                if name == "align" {
                    match Vocabulary.align_of(value) {
                        none => { self.faults.push("align=\"{value}\" is not one of start, center, end, stretch") }
                        some(mode) => { self.set_align(element, mode) }
                    }
                    return
                }
                if name == "justify" {
                    match Vocabulary.justify_of(value) {
                        none => { self.faults.push("justify=\"{value}\" is not a justification cortado knows") }
                        some(mode) => { self.set_justify(element, mode) }
                    }
                    return
                }
                // Parsed here rather than in the markup compiler, so `#abc`
                // means one thing in `<ColorWell />` and in a shader.
                if Vocabulary.is_colour(name) {
                    if self.refuse_unless_carried(element, name) { return }
                    match widgets.Rgba.of_hex(value) {
                        err(problem) => { self.faults.push(problem.msg) }
                        ok(shade) => {
                            element.set(Attribute.of_whole(Vocabulary.property_of(name),
                                                           widgets.ColorWell.pack(shade)))
                        }
                    }
                    return
                }
                self.faults.push("<{element.tag}> has no attribute called '{name}'")
            }
        }
    }

    /// Subscribes to an event by its markup name — `click`, `change`,
    /// `commit`, `focus`.
    pub fn on(name: string, action: fn(events.UiEvent)) {
        match self.current() {
            none => { self.faults.push("on:{name} with no element open") }
            some(element) => {
                match Vocabulary.event_of(name) {
                    none => { self.faults.push("on:{name} is not an event cortado raises") }
                    some(kind) => { element.listen(kind, action) }
                }
            }
        }
    }

    /// Subscribes by kind, for a component written by hand that would rather
    /// name the event than spell it.
    pub fn on_kind(kind: events.EventKind, action: fn(events.UiEvent)) {
        match self.current() {
            none => { self.faults.push("{kind.name()} handler with no element open") }
            some(element) => { element.listen(kind, action) }
        }
    }

    /// Shows a component the parent already holds.
    ///
    /// Beans has no overloading, so this and `child<T>` are two names for two
    /// ownerships: here the parent owns the instance, usually in a field;
    /// there the mount does, because markup names a type rather than an
    /// object. Both keep their state across renders.
    ///
    /// `key` names this child among its siblings and must be unique within the
    /// component that wrote it. It is what lets the child keep its state
    /// across renders: the same key is the same child, holding whatever it was
    /// holding, even when the markup around it moved.
    ///
    /// The parent normally keeps the child in a field, which is where its
    /// state naturally lives:
    ///
    /// ```beans
    /// total: SubTotal = new SubTotal()
    /// pub override fn render(into: component.Builder) {
    ///     into.open("VStack")
    ///     into.child("total", self.total)
    ///     into.close()
    /// }
    /// ```
    pub fn show(key: string, sub: Component) {
        match self.composer {
            none => {
                self.faults.push("child \"{key}\" cannot be rendered: this builder is not attached to a mount")
            }
            some(who) => {
                // The composer is handed the qualified key and the fault names
                // the one the author wrote, which is why the qualifying
                // happens here and not inside the mount.
                match who.compose(self.scoped_key(key), sub) {
                    ok(subtree) => { self.embed(subtree) }
                    err(problem) => { self.faults.push("child \"{key}\": {problem.msg}") }
                }
            }
        }
    }

    /// Shows a component of type `T` here, building it the first time.
    ///
    /// What markup emits. `<Price drink={self.drink} />` becomes
    ///
    /// ```beans
    /// into.child<Price>("c4", fn(c: Price) { c.drink = self.drink })
    /// ```
    ///
    /// The mount owns the instance and hands the same one back on every later
    /// render, so the child keeps its state; `setup` runs each time, which is
    /// what carries a changed parameter down.
    ///
    /// Generic, and on a concrete class rather than on the `Composer`
    /// interface, because Beans refuses generic interface methods. The
    /// interface answers a boxed value and the downcast happens here — legal
    /// because a `reflect.Value` is the one source `as?` may narrow to an
    /// instantiation.
    pub fn child<T>(key: string, setup: fn(T)) {
        match self.composer {
            none => {
                self.faults.push("<{type_of(T).name()}> cannot be rendered: this builder is not attached to a mount")
                return
            }
            some(who) => {
                // The same qualification `show` applies below, so the instance
                // this obtains and the subtree that gets composed are one
                // child and not two.
                match who.obtain(self.scoped_key(key), type_of(T)) {
                    err(problem) => {
                        self.faults.push("<{type_of(T).name()}>: {problem.msg}")
                    }
                    ok(boxed) => {
                        match boxed as? T {
                            none => {
                                self.faults.push("<{type_of(T).name()}> came back as something else")
                            }
                            some(built) => {
                                setup(built)
                                match boxed as? Component {
                                    none => {
                                        self.faults.push("<{type_of(T).name()}> is not a Component")
                                    }
                                    some(shown) => { self.show(key, shown) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- fragments ----

    /// Places a template this component's parent supplied: what `$slot`
    /// compiles to.
    ///
    /// A fragment is a `fn(Builder)` the parent wrote and the child places.
    /// The body is **written** in the parent's markup — so `self` inside it is
    /// the parent, and it reads the parent's fields — and **run** here,
    /// against this builder, so the controls it describes land wherever the
    /// child put its `$slot`. That split is the whole feature: a `<Tile>`
    /// decides where its content goes and the screen around it decides what
    /// the content is.
    ///
    /// ### `site` is load-bearing, not decoration
    ///
    /// `site` names **where this placement is** — which `$slot` of this render,
    /// and which turn of the `$for` around it. cortado-bx writes `"2"` for the
    /// third placement in a render and `"2.{row}"` for one inside a loop, the
    /// same two-part identity it gives a component tag. It is what makes
    /// placing one template at two sites — or on two rows — produce two
    /// independent children rather than one shared between them, and it is
    /// needed because **a fragment body restarts key numbering at 0**:
    /// cortado-bx emits a fragment body in a counter scope of its own, so the
    /// first component tag inside any fragment body asks for the key `c0` —
    /// which is exactly what the placing component's own first component tag
    /// asks for.
    ///
    /// So every child key written while the body runs is qualified with
    /// `$f{site}/`. A `$` can never begin a key cortado-bx generates — those
    /// are `c{n}` and `c{n}.{row}` — so a qualified key can never collide with
    /// an unqualified one, and two placements differ because their site does.
    /// It is the move `$for` already makes with the row index, which is a
    /// suffix for the same reason: a counter that restarts needs something
    /// from outside it to tell its numbers apart.
    ///
    /// A string rather than a number, and the loop is why: a `$slot` in a
    /// `$for` body is *one* emitted call run once per row, so the number in it
    /// is the same on every turn and only the row tells the turns apart. A
    /// number could carry the site or the row and not both.
    ///
    /// ### Two layers of scoping, and why neither covers the other
    ///
    /// `Mount.scoped_key` qualifies a key by the component whose `render` is
    /// running, because cortado-bx numbers from 0 in every render it writes.
    /// This qualifies a key by the fragment placement it was asked for inside,
    /// because cortado-bx numbers from 0 *again* inside every fragment body.
    /// The mount cannot do this one: a fragment body is a closure it never
    /// sees, called from inside a render it has already entered. The builder
    /// cannot do the mount's: it does not know which component it is building
    /// for, and must not — it is the same object whether it is building a real
    /// window or a tree for a test. The mount applies its layer to whatever
    /// this hands it, so a component inside the first `$slot` of a `<Tile>`
    /// ends up under `<the tile>/$f0/c0`.
    ///
    /// ### Element keys are deliberately *not* qualified
    ///
    /// `key=` on a control is not identity for state; it is the name
    /// `Stage.control` and `Stage.widget` look a control up by once it is
    /// real. Qualifying it would make that name unreachable — the author
    /// writes `key="plot"` and would have to ask for `$f0/plot`, a string they
    /// have no way to know. So two placements of one body do produce two
    /// siblings carrying one key: the differ matches keyed siblings
    /// first-untaken, which leaves each in its own place, and `Stage.control`
    /// answers the first of them.
    pub fn fragment(site: string, body: fn(Builder)) {
        let outer: string = self.fragment_scope
        self.fragment_scope = "{outer}$f{site}/"
        body(self)
        self.fragment_scope = outer
    }

    /// A child's key, qualified by the fragment placement it was asked for
    /// inside. Outside every fragment it is the key itself, so nothing that
    /// places no fragment is affected at all.
    fn scoped_key(key: string) -> string {
        if self.fragment_scope == "" { return key }
        return "{self.fragment_scope}{key}"
    }

    /// Splices an already-built subtree in as a child.
    ///
    /// This is how one component shows another. The child's own render
    /// produced the subtree — or, when nothing about the child changed, the
    /// subtree it produced last time, unchanged and not re-rendered.
    pub fn embed(subtree: Element) {
        if self.open_stack.len() == 0 {
            match self.root {
                none => { self.root = some(subtree) }
                some(already) => {
                    self.faults.push("a render has two roots: <{already.tag}> and <{subtree.tag}>")
                }
            }
            return
        }
        let parent: Element = self.open_stack[self.open_stack.len() - 1]
        self.settle(subtree, parent)
        parent.add(subtree)
    }

    /// Answers the requirement a component's root element carried out of its
    /// own render, now that the container it landed in is known.
    fn settle(subtree: Element, parent: Element) {
        if subtree.pending == "" { return }
        var answered: bool = false
        match parent.arranger {
            none => {}
            some(arranger) => {
                if subtree.pending == "flex" {
                    match arranger as? layout.FlexLayout {
                        some(run) => { answered = true }
                        none => {}
                    }
                } else {
                    match arranger as? layout.AbsoluteLayout {
                        some(box) => { answered = true }
                        none => {}
                    }
                }
            }
        }
        if !answered {
            self.faults.push(Builder.wrong_parent(subtree.tag, subtree.pending_name, subtree.pending))
        }
        subtree.pending = ""
        subtree.pending_name = ""
    }

    // ---- the result ----

    /// The tree, or every mistake in the render that produced it.
    pub fn finish() -> Result<Element> {
        if self.open_stack.len() > 0 {
            self.faults.push("<{self.open_stack[self.open_stack.len() - 1].tag}> was never closed")
        }
        if self.faults.len() > 0 {
            var joined: string = ""
            for fault: string in self.faults {
                if joined != "" { joined = "{joined}; " }
                joined = "{joined}{fault}"
            }
            return err(joined, "bad_render")
        }
        match self.root {
            none => { return err("a render produced nothing", "empty_render") }
            some(element) => { return ok(element) }
        }
    }

    // ---- internals ----

    fn push(element: Element) {
        self.open_stack.push(element)
    }

    fn current() -> Option<Element> {
        if self.open_stack.len() == 0 { return none }
        return some(self.open_stack[self.open_stack.len() - 1])
    }

    /// Whether the element the open one sits inside shares out leftover space.
    ///
    /// A root element has no parent here, so it answers false — which is
    /// right: whatever mounts it decides its size, and a `grow` on it would be
    /// read by nobody.
    fn parent_flexes() -> bool {
        if self.open_stack.len() < 2 { return false }
        match self.open_stack[self.open_stack.len() - 2].arranger {
            none => { return false }
            some(arranger) => {
                match arranger as? layout.FlexLayout {
                    some(run) => { return true }
                    none => { return false }
                }
            }
        }
    }

    /// Whether `name` may be written on `element` here.
    ///
    /// A parent in this render answers at once. A component's root element has
    /// none yet — its render is a builder of its own — so the requirement is
    /// recorded and `embed` answers it against the container it lands in.
    fn parent_allows(element: Element, name: string, want: string) -> bool {
        if self.open_stack.len() < 2 {
            if element.pending != "" && element.pending != want {
                self.faults.push("<{element.tag}> asks both to be placed and to flex, and no one container does both")
                return false
            }
            element.pending = want
            element.pending_name = name
            return true
        }
        if want == "flex" {
            if self.parent_flexes() { return true }
            self.faults.push(Builder.wrong_parent(element.tag, name, want))
            return false
        }
        if self.parent_places() { return true }
        self.faults.push(Builder.wrong_parent(element.tag, name, want))
        return false
    }

    /// The one sentence for a requirement no container around it answers,
    /// written once so a deferred refusal reads the same as an immediate one.
    static fn wrong_parent(tag: string, name: string, want: string) -> string {
        if want == "flex" {
            return "{name} is shared out by a flexing run, and <{tag}> sits in one that does not flex — write <VFlex> or <HFlex> around it, or set width/height instead"
        }
        return "{name} is a coordinate a placing container reads, and <{tag}> sits in one that arranges its children itself — write <Box> around it, or use spacing and padding instead"
    }

    /// Whether the container around this element places its children at the
    /// coordinates they carry, which is the only thing that reads `x` and `y`.
    fn parent_places() -> bool {
        if self.open_stack.len() < 2 { return false }
        match self.open_stack[self.open_stack.len() - 2].arranger {
            none => { return false }
            some(arranger) => {
                match arranger as? layout.AbsoluteLayout {
                    some(box) => { return true }
                    none => { return false }
                }
            }
        }
    }

    // `spacing` and `padding` configure the container's own arrangement;
    // everything else is what this element asks of the run around it. The
    // split matters because the two live on different objects and are read at
    // different moments — one when this element lays its children out, the
    // other when this element's parent lays *it* out.
    fn layout_number(element: Element, name: string, value: f64) {
        if name == "spacing" {
            match element.arranger {
                none => { self.faults.push("<{element.tag}> has no children to space") }
                some(arranger) => {
                    match arranger as? layout.StackLayout {
                        some(run) => { run.set_spacing(value) }
                        none => { self.faults.push("<{element.tag}> does not arrange its children in a run, so it has no spacing") }
                    }
                }
            }
            return
        }
        if name == "padding" {
            self.set_padding(element, geometry.EdgeInsets.all(value))
            return
        }
        if name == "margin" {
            element.spec.margin = geometry.EdgeInsets.all(value)
            return
        }
        // A per-edge form writes only the edges it names and keeps the rest, in
        // source order: `padding={8} padding_x={16}` is 8 above and below, 16 at the sides.
        let pad_edge: string = Vocabulary.padding_edge(name)
        if pad_edge != "" {
            self.set_padding(element, with_edge(self.padding_of(element), pad_edge, value))
            return
        }
        let margin_edge: string = Vocabulary.margin_edge(name)
        if margin_edge != "" {
            element.spec.margin = with_edge(element.spec.margin, margin_edge, value)
            return
        }
        // `grow`, `shrink` and `basis` are read by a flexing run and by
        // nothing else. An author who writes `grow={1}` inside a plain
        // `<HStack>` gets a control that does not grow and no explanation —
        // the exact silent no-op cortado refuses everywhere else — so the
        // parent is checked here, where both markup and hand-written code go
        // through.
        if name == "grow" || name == "shrink" || name == "basis" {
            if !self.parent_allows(element, name, "flex") { return }
            if name == "grow" { element.spec.grow = value }
            if name == "shrink" { element.spec.shrink = value }
            if name == "basis" { element.spec.basis = value }
            return
        }
        // `x` and `y` are read by a placing run and by nothing else, the
        // same shape as `grow` above: an author who writes `x={20}` inside a
        // `<VStack>` would get a control at the run's coordinate and no word
        // about why.
        if name == "x" || name == "y" {
            if !self.parent_allows(element, name, "place") { return }
            if name == "x" { element.spec.x = value }
            if name == "y" { element.spec.y = value }
            return
        }
        if name == "width" {
            element.spec.min_width = value
            element.spec.max_width = value
            return
        }
        if name == "height" {
            element.spec.min_height = value
            element.spec.max_height = value
            return
        }
        self.faults.push("<{element.tag}> has no attribute called '{name}'")
    }

    /// What `element` keeps inside its box so far, for a per-edge attribute to
    /// add one edge to. A leaf answers zero, and `set_padding` refuses it a call later.
    fn padding_of(element: Element) -> geometry.EdgeInsets {
        match element.arranger {
            none => { return geometry.EdgeInsets.zero() }
            some(arranger) => { return arranger.padding() }
        }
    }

    fn set_padding(element: Element, insets: geometry.EdgeInsets) {
        match element.arranger {
            none => { self.faults.push("<{element.tag}> has no children to pad") }
            some(arranger) => {
                match arranger as? layout.StackLayout {
                    some(run) => { run.set_padding(insets); return }
                    none => {}
                }
                match arranger as? layout.GridLayout {
                    some(grid) => { grid.set_padding(insets); return }
                    none => {}
                }
                match arranger as? layout.AbsoluteLayout {
                    some(box) => { box.set_padding(insets); return }
                    none => {}
                }
                self.faults.push("<{element.tag}> cannot be padded")
            }
        }
    }

    // `align` on a container is the default for its children; `align` on a
    // child is that child's own. One name, two meanings, told apart by whether
    // the element arranges anything — which is what an author means when they
    // write it.
    fn set_align(element: Element, mode: geometry.Align) {
        match element.arranger {
            none => { element.spec.align = mode }
            some(arranger) => {
                match arranger as? layout.StackLayout {
                    some(run) => { run.set_align(mode); return }
                    none => {}
                }
                match arranger as? layout.GridLayout {
                    some(grid) => { grid.set_align(mode); return }
                    none => {}
                }
                element.spec.align = mode
            }
        }
    }

    fn set_justify(element: Element, mode: layout.Justify) {
        match element.arranger {
            none => { self.faults.push("<{element.tag}> has no children to justify") }
            some(arranger) => {
                match arranger as? layout.StackLayout {
                    some(run) => { run.set_justify(mode) }
                    none => { self.faults.push("<{element.tag}> does not arrange its children in a run, so it has no justification") }
                }
            }
        }
    }
}

/// `insets` with one edge replaced, or both edges of one axis for `x` and `y`.
/// Any other edge name changes nothing, and `Vocabulary` never answers one.
fn with_edge(insets: geometry.EdgeInsets, edge: string, value: f64) -> geometry.EdgeInsets {
    var out: geometry.EdgeInsets = insets
    if edge == "top" { out.top = value }
    if edge == "right" { out.right = value }
    if edge == "bottom" { out.bottom = value }
    if edge == "left" { out.left = value }
    if edge == "x" { out.left = value; out.right = value }
    if edge == "y" { out.top = value; out.bottom = value }
    return out
}
