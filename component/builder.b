// What a component renders into.
package component

import cortado.widgets
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
                element.set(Attribute.of_flag(property, value))
            }
        }
    }

    /// A numeric property, or one of the layout numbers — `spacing`,
    /// `padding`, `grow`, `shrink`, `basis`, `margin`, `width`, `height`.
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
                match who.compose(key, sub) {
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
                match who.obtain(key, type_of(T)) {
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
        self.open_stack[self.open_stack.len() - 1].add(subtree)
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
        // `grow`, `shrink` and `basis` are read by a flexing run and by
        // nothing else. An author who writes `grow={1}` inside a plain
        // `<HStack>` gets a control that does not grow and no explanation —
        // the exact silent no-op cortado refuses everywhere else — so the
        // parent is checked here, where both markup and hand-written code go
        // through.
        if name == "grow" || name == "shrink" || name == "basis" {
            if !self.parent_flexes() {
                self.faults.push(
                    "{name} is shared out by a flexing run, and <{element.tag}> sits in one that does not flex — write <VFlex> or <HFlex> around it, or set width/height instead")
                return
            }
            if name == "grow" { element.spec.grow = value }
            if name == "shrink" { element.spec.shrink = value }
            if name == "basis" { element.spec.basis = value }
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
