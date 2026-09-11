// How one component shows another.
package component

/// Renders a child component on a parent's behalf.
///
/// The `Builder` a parent renders into does not know what a mount is, and must
/// not: it is the same object whether it is building a real window, a test
/// tree or a subtree for comparison. So `Builder.child` asks this, and the
/// mount is what implements it.
///
/// The implementation is responsible for everything the parent should not have
/// to think about: filling the child's injected fields the first time it is
/// seen, running its lifecycle in order, and — when the child says it has
/// nothing new to show — handing back the subtree it produced last time
/// instead of rendering it again.
pub interface Composer {
    fn compose(key: string, child: Component) -> Result<Element>
}
