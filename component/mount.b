// A component tree, alive on a surface.
package component

import cortado.widgets
import cortado.events
import cortado.layout
import cortado.geometry
import std.reflect

/// Owns a root component, the controls it produced, and everything needed to
/// keep the two in step.
///
/// This is the class an application actually holds. Give it a container to
/// fill and a component to show; call `refresh()` whenever something changed.
/// Each refresh renders, diffs against the last render, applies only the
/// difference, and lays the result out.
///
/// ```beans
/// var mount: component.Mount = new component.Mount(root, app.router)
/// mount.use_services(container)          // optional
/// mount.show(new OrderScreen())?
/// mount.set_bounds(window.content_size()?)
/// mount.refresh()?
/// ```
///
/// ### Why the mount holds the components and not the other way round
///
/// A component never points back here. `request_render` sets a flag on the
/// component and the mount asks; a back-reference would make a cycle, and an
/// object that dies inside a reference cycle never runs its `deinit` — which
/// for a tree holding native controls is exactly the leak nobody notices. The
/// mount visits every component it owns on every refresh anyway, so asking
/// costs nothing that being told would have saved.
pub class Mount implements Composer {
    root: widgets.Widget
    router: events.EventRouter
    sheet: widgets.WidgetLayout
    solver: layout.Solver

    top: Option<Component> = none
    shown: Option<Element> = none
    services: Option<ServiceSource> = none

    /// The plan per component type, worked out on that type's first mount and
    /// kept for the life of the application.
    plans: Map<string, MountPlan> = {}

    /// Child components this mount has already prepared, by the key their
    /// parent gave them.
    prepared: Map<string, Component> = {}
    /// What each child rendered last time, so a child that says it has nothing
    /// new can be spliced back in without running its render at all.
    cached: Map<string, Element> = {}
    /// Which keys this render has used, so a duplicate is reported rather than
    /// silently making two components share one identity.
    used: Map<string, bool> = {}

    /// Which element each live control stands for. Rebuilt after every apply.
    by_handle: Map<u64, Element> = {}

    /// The control the element tree's root became — the single child of the
    /// box this mount was given to fill.
    face: Option<widgets.Widget> = none

    bounds: geometry.Size = geometry.Size.zero()
    renders: int = 0

    pub fn init(root: widgets.Widget, router: events.EventRouter) {
        self.root = root
        self.router = router
        self.sheet = new widgets.WidgetLayout()
        self.solver = new layout.Solver(self.sheet)
    }

    /// Where `@inject` fields come from. Without one, a component that has any
    /// is refused at mount rather than mounted with them empty.
    pub fn use_services(source: ServiceSource) {
        self.services = some(source)
    }

    /// The room the tree is laid out in. Set it from the surface's content
    /// size, and again whenever the surface resizes.
    pub fn set_bounds(size: geometry.Size) {
        self.bounds = size
    }

    pub fn reading(direction: layout.TextDirection) {
        self.solver.set_direction(direction)
    }

    pub fn scale(value: f64) {
        self.solver.set_scale(value)
    }

    /// How many renders have happened. A test's cheapest proof that a
    /// `should_render` really pruned something.
    pub fn render_count() -> int {
        return self.renders
    }

    /// Puts a component on this surface and renders it for the first time.
    pub fn show(component: Component) -> Result<bool> {
        self.top = some(component)
        self.prepare(component)?
        return self.refresh()
    }

    /// Renders, applies the difference, and lays the result out.
    ///
    /// Safe to call when nothing changed: the differ answers an empty list and
    /// no platform call happens at all.
    pub fn refresh() -> Result<bool> {
        match self.top {
            none => { return err("this mount has nothing to show", "not_mounted") }
            some(component) => {
                self.used = {}
                let next: Element = self.render_one(component)?
                var differ: Differ = new Differ()
                let changes: List<Change> = differ.diff(self.shown, next)
                var applier: Applier = new Applier(self.root, self.router, self)
                applier.apply(changes)?
                applier.index(next)?
                self.face = some(applier.face()?)
                self.shown = some(next)
                self.settle_all()
                self.lay_out()?
                return ok(true)
            }
        }
    }

    /// Takes everything down: unsubscribes, unmounts, and empties the
    /// container.
    pub fn close() -> Result<bool> {
        match self.top {
            none => {}
            some(component) => {
                component.on_unmount()
                component.note_mounted(false)
            }
        }
        for key: string in self.prepared.keys() {
            match self.prepared.get(key) {
                some(child) => {
                    child.on_unmount()
                    child.note_mounted(false)
                }
                none => {}
            }
        }
        match self.root as? widgets.Container {
            none => {}
            some(box) => {
                var back: int = box.count() - 1
                for back >= 0 {
                    match box.child_at(back) {
                        // The whole subtree, not just the child: a
                        // registration is per control, and forgetting only the
                        // top of a tree leaves one dead closure per descendant
                        // holding this mount alive for the life of the process.
                        some(child) => { self.forget_all(child) }
                        none => {}
                    }
                    box.remove(back)?
                    back = back - 1
                }
            }
        }
        self.prepared = {}
        self.cached = {}
        self.by_handle = {}
        self.shown = none
        self.top = none
        self.face = none
        return ok(true)
    }

    fn forget_all(control: widgets.Widget) {
        self.router.forget(control.handle())
        self.by_handle.remove(control.handle().raw)
        for child: widgets.Widget in control.children() {
            self.forget_all(child)
        }
    }

    // ---- rendering ----

    fn render_one(component: Component) -> Result<Element> {
        var into: Builder = new Builder()
        into.set_composer(self)
        component.render(into)
        self.renders = self.renders + 1
        return into.finish()
    }

    /// `Composer`: renders a child on its parent's behalf.
    ///
    /// Three things happen here that the parent should not have to think
    /// about. A child seen for the first time is prepared — injected, its
    /// parameters announced, `on_init` run — before anything asks it to
    /// render. A child that says `should_render` is false is not rendered at
    /// all, and the subtree it produced last time is handed back untouched.
    /// And a key used twice in one render is refused, because two components
    /// sharing an identity would take each other's state.
    pub fn compose(key: string, child: Component) -> Result<Element> {
        match self.used.get(key) {
            some(already) => {
                return err("two children in one render both use the key \"{key}\"", "duplicate_key")
            }
            none => {}
        }
        self.used[key] = true

        var first: bool = false
        match self.prepared.get(key) {
            none => {
                self.prepare(child)?
                self.prepared[key] = child
                first = true
            }
            some(held) => {}
        }

        if !first && !child.is_dirty() && !child.should_render() {
            match self.cached.get(key) {
                some(before) => { return ok(before) }
                none => {}
            }
        }

        let subtree: Element = self.render_one(child)?
        self.cached[key] = subtree
        return ok(subtree)
    }

    // ---- preparation ----

    /// Fills a component's injected fields and runs the start of its life.
    fn prepare(component: Component) -> Result<bool> {
        // `reflect.value` boxes the *runtime* type, so a subclass mounted
        // through a `Component` reference is reflected as itself and not as
        // the base — which is the whole point, since the annotations are on
        // the subclass.
        let receiver: reflect.Value = reflect.value(component)
        let described: reflect.Type = receiver.type()
        let plan: MountPlan = self.plan_for(described)
        var problems: List<string> = []
        for fault: string in plan.faults {
            problems.push(fault)
        }
        if plan.bindings.len() > 0 {
            match self.services {
                none => {
                    for binding: InjectBinding in plan.bindings {
                        problems.push(
                            "{described.qualified_name()}.{binding.field.name()} is @inject, but this mount has no service container to fill it from")
                    }
                }
                some(source) => {
                    for binding: InjectBinding in plan.bindings {
                        if binding.fault != "" {
                            problems.push(binding.fault)
                            continue
                        }
                        match source.provide(binding.wanted) {
                            err(problem) => {
                                problems.push("{described.qualified_name()}.{binding.field.name()}: {problem}")
                            }
                            ok(value) => {
                                match binding.field.set(receiver.copy(), value) {
                                    ok(done) => {}
                                    err(problem) => {
                                        problems.push("{described.qualified_name()}.{binding.field.name()}: {problem.message()}")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if problems.len() > 0 {
            var joined: string = ""
            for problem: string in problems {
                if joined != "" { joined = "{joined}; " }
                joined = "{joined}{problem}"
            }
            return err(joined, "injection_failed")
        }
        component.on_params_set()
        component.on_init()
        return ok(true)
    }

    fn plan_for(described: reflect.Type) -> MountPlan {
        let key: string = described.qualified_name()
        match self.plans.get(key) {
            some(found) => { return found }
            none => {}
        }
        let made: MountPlan = MountPlan.of(described)
        self.plans[key] = made
        return made
    }

    fn settle_all() {
        match self.top {
            none => {}
            some(component) => { self.settle_one(component) }
        }
        for key: string in self.prepared.keys() {
            match self.prepared.get(key) {
                some(child) => { self.settle_one(child) }
                none => {}
            }
        }
    }

    fn settle_one(component: Component) {
        component.settle()
        if !component.is_mounted() {
            component.note_mounted(true)
            component.on_mount()
        }
    }

    // ---- layout ----

    /// Builds a layout tree that mirrors the element tree and solves it.
    ///
    /// Rebuilt each refresh rather than patched. The tree is small, the nodes
    /// hold no platform handles, and a layout tree patched in step with a
    /// widget tree is a second reconciler to keep correct — one whose bugs
    /// would show up as controls in the wrong place with every frame otherwise
    /// looking right.
    fn lay_out() -> Result<bool> {
        match self.shown {
            none => { return ok(true) }
            some(element) => {
                match self.face {
                    none => { return ok(true) }
                    some(control) => {
                        self.sheet = new widgets.WidgetLayout()
                        self.solver = new layout.Solver(self.sheet)
                        var page: layout.LayoutNode = self.node_for(element, control)
                        self.solver.solve(page,
                            geometry.Rect.at(geometry.Point.zero(), self.bounds))?
                        self.sheet.apply(page)?
                    }
                }
                return ok(true)
            }
        }
    }

    fn node_for(element: Element, control: widgets.Widget) -> layout.LayoutNode {
        var node: layout.LayoutNode = layout.LayoutNode.leaf(element.tag, -1)
        match element.arranger {
            none => { node = self.sheet.leaf(element.tag, control) }
            some(arranger) => { node = self.sheet.group(element.tag, control, arranger) }
        }
        node.spec = element.spec
        match control as? widgets.Container {
            none => { return node }
            some(box) => {
                var index: int = 0
                for index: int in 0..element.count() {
                    match box.child_at(index) {
                        some(child) => { node.add(self.node_for(element.child_at(index), child)) }
                        none => {}
                    }
                }
            }
        }
        return node
    }

    // ---- events ----

    /// Framework use: records which element a control stands for.
    pub fn record(handle: u64, element: Element) {
        self.by_handle[handle] = element
    }

    /// Framework use: forgets a control that has gone.
    pub fn release(handle: u64) {
        self.by_handle.remove(handle)
    }

    /// Delivers an event to the handler the current render put on that
    /// control.
    ///
    /// The lookup happens now, not when the handler subscribed, which is what
    /// makes a re-rendered closure take effect with no platform call. A
    /// control whose element has gone — an event already in flight when its
    /// row was removed — is dropped rather than reaching a stale closure.
    pub fn dispatch(handle: u64, kind: events.EventKind, event: events.UiEvent) {
        match self.by_handle.get(handle) {
            none => { return }
            some(element) => {
                match element.listener(kind) {
                    none => { return }
                    some(listener) => { listener.fire(event) }
                }
            }
        }
    }

    /// Whether anything this mount owns has asked to be rendered again.
    pub fn is_dirty() -> bool {
        match self.top {
            none => { return false }
            some(component) => { if component.is_dirty() { return true } }
        }
        for key: string in self.prepared.keys() {
            match self.prepared.get(key) {
                some(child) => { if child.is_dirty() { return true } }
                none => {}
            }
        }
        return false
    }

    /// Renders again only if something asked. What an event loop calls after
    /// handling an event.
    pub fn refresh_if_needed() -> Result<bool> {
        if !self.is_dirty() {
            return ok(false)
        }
        self.refresh()?
        return ok(true)
    }
}
