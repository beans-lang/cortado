// Where the machine is.
package device

/// One fix: a place, how sure the platform is of it, and which way the machine
/// is going.
///
/// A struct rather than a class because it is a reading and not a thing: two
/// fixes a second apart are two values, and a program that kept one and
/// compared it with the next would want a copy rather than a reference.
pub struct Place {
    pub latitude: f64
    pub longitude: f64
    /// How far out it might be, in metres. A phone indoors answers hundreds.
    pub accuracy: f64
    /// Which way the machine is *going*, in degrees clockwise from north, or
    /// **-1 where nobody knows** — which is every machine that is standing
    /// still, because a course is derived from movement. It is not a compass
    /// heading and must not be drawn as one.
    pub heading: f64

    /// Whether a heading was reported at all.
    pub fn has_heading() -> bool {
        return self.heading >= 0.0
    }

    /// The line a golden carries. Deliberately not the numbers: a test that
    /// printed where the machine was would be a test of where it was run.
    pub fn show() -> string {
        return "a place accurate to about {self.accuracy as int} m"
    }
}
