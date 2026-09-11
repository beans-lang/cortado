// A piece of user interface, and its life.
package component

/// Something that describes an interface and can be shown.
///
/// A component is an ordinary Beans class. Its fields are its state, its
/// methods are its behaviour, and `render` says what it should look like right
/// now. It never touches a control: it describes one, and cortado works out
/// what to change.
///
/// ```beans
/// @view
/// pub class Counter extends component.Component {
///     @param pub start: int = 0
///     @inject pub log: Journal
///     count: int = 0
///
///     pub fn init() { super.init() }
///     pub override fn on_init() { self.count = self.start }
///
///     pub override fn render(into: component.Builder) {
///         into.open("HStack")
///         into.number("spacing", 8.0)
///             into.open("Label")
///             into.text("{self.count}")
///             into.close()
///             into.open("Button")
///             into.text("More")
///             into.on("click", fn(event: events.UiEvent) { self.bump() })
///             into.close()
///         into.close()
///     }
///
///     fn bump() {
///         self.count = self.count + 1
///         self.request_render()
///     }
/// }
/// ```
///
/// ### The order things happen in
///
/// 1. The component is built — by `new`, or by the container when it has
///    constructor parameters.
/// 2. `@inject` fields are filled and `@param` fields are set.
/// 3. `on_init` runs, once, with everything in place.
/// 4. `on_params_set` runs, now and every time a parameter changes after.
/// 5. `render` runs, and its result reaches the platform.
/// 6. `on_mount` runs, once, after real controls exist.
/// 7. `on_unmount` runs when the component goes away.
///
/// `on_init` is separate from `init` precisely because of step 2: an `init`
/// body cannot see an injected field, since nothing has filled it yet. Putting
/// setup in `init` and wondering why a service is empty is the mistake this
/// ordering removes.
pub abstract class Component {
    /// Set by `request_render`, cleared by the framework once the render has
    /// happened.
    ///
    /// A flag and not a callback into whatever is showing this component. A
    /// back-reference would be a cycle — the mount holds the component, the
    /// component holds the mount — and a cycle whose members hold platform
    /// resources is exactly the shape that never runs `deinit`. The mount
    /// already visits every component it owns; asking is cheaper than being
    /// told, and it cannot leak.
    needs_render: bool = false
    mounted: bool = false

    pub fn init() {}

    /// Describe what this component should look like, now.
    ///
    /// Called whenever something might have changed. It must not have side
    /// effects: it is called more often than an author expects and, after a
    /// `should_render` says no, not at all.
    pub abstract fn render(into: Builder)

    /// Run once, after injection and parameters, before the first render.
    pub fn on_init() {}

    /// Run after the parameters are set — the first time and every later time
    /// one changes.
    pub fn on_params_set() {}

    /// Run once, after this component's controls exist on the platform. The
    /// place to ask a control for something only it knows, or to start
    /// something that has to stop in `on_unmount`.
    pub fn on_mount() {}

    /// Run when this component goes away. Stop here whatever `on_mount`
    /// started: a timer, a subscription, a file. `deinit` is not the place —
    /// a component caught in a reference cycle never runs one.
    pub fn on_unmount() {}

    /// Whether this component needs re-rendering.
    ///
    /// The default is yes, which is always correct and sometimes wasteful.
    /// Override it to compare what this component actually depends on; a
    /// component whose answer is no is not rendered, and the subtree it
    /// produced last time is reused untouched.
    pub fn should_render() -> bool {
        return true
    }

    /// Ask to be rendered again. Call it after changing state that the
    /// interface shows.
    pub fn request_render() {
        self.needs_render = true
    }

    pub fn is_dirty() -> bool {
        return self.needs_render
    }

    /// Framework use: clears the flag once the render it asked for has
    /// happened.
    pub fn settle() {
        self.needs_render = false
    }

    pub fn is_mounted() -> bool {
        return self.mounted
    }

    /// Framework use: records that this component's controls exist.
    pub fn note_mounted(state: bool) {
        self.mounted = state
    }
}
