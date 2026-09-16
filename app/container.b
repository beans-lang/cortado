// barista, behind the interface cortado asks for.
package cortado_app

import github.com/beans-lang/barista
import cortado.component
import std.reflect

/// Fills `@inject` fields from a barista provider.
///
/// The whole of the dependency between cortado and barista is this class. The
/// component layer asks a `ServiceSource` for a type and gets a boxed value
/// back; everything about lifetimes, scopes, disposal and constructor
/// resolution stays inside barista, where it belongs.
///
/// The split matters more than it looks. `cortado.component` has no dependency
/// on any container, so an application with its own idea of where services
/// come from writes twenty lines instead of adopting one — and cortado's own
/// test suite mounts components with a hand-written source, so a bug in the
/// container cannot make the framework's gate red and a bug in the framework
/// cannot hide behind the container.
pub class Container implements component.ServiceSource, component.Activator {
    provider: barista.ServiceProvider

    pub fn init(provider: barista.ServiceProvider) {
        self.provider = provider
    }

    /// Resolves a service the container was told about.
    pub fn provide(described: reflect.Type) -> Result<reflect.Value, string> {
        match self.provider.resolve_type(described) {
            ok(value) => { return ok(value) }
            err(problem) => { return err(problem.msg) }
        }
    }

    /// Whether this container could answer, without building anything.
    ///
    /// Answering without constructing is what lets a whole application's
    /// dependencies be checked at startup. A question that had to build the
    /// object to be asked is not one you can ask about two hundred component
    /// types before opening a window.
    pub fn knows(described: reflect.Type) -> bool {
        return self.provider.provides(described)
    }

    /// Builds a type the container was never told about, resolving its
    /// initializer's parameters. This is `component.Activator`.
    ///
    /// It is how a component named in markup — `<Price drink={...} />` names a
    /// type, not an object — is created, and how one with constructor
    /// dependencies works there, without registering every screen in the
    /// application as a service.
    pub fn build(described: reflect.Type) -> Result<reflect.Value, string> {
        match self.provider.activate(described) {
            ok(value) => { return ok(value) }
            err(problem) => { return err(problem.msg) }
        }
    }

    pub fn provider_ref() -> barista.ServiceProvider {
        return self.provider
    }
}
