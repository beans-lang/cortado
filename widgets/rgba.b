// One pixel, as the platform painted it.
package widgets

/// A colour read back out of a snapshot: four channels, each 0 to 255.
///
/// A struct rather than a class because it is a value and there are a great
/// many of them — a hundred-by-forty snapshot holds four thousand — and
/// because nothing about a colour needs identity.
pub struct Rgba {
    pub red: int = 0
    pub green: int = 0
    pub blue: int = 0
    /// 255 is opaque. A pixel nothing painted is 0 everywhere, alpha
    /// included, which is what makes "nothing was drawn here" a fact a test
    /// can assert rather than a guess about the allocator.
    pub alpha: int = 0

    pub fn same_as(other: Rgba) -> bool {
        return self.red == other.red && self.green == other.green &&
               self.blue == other.blue && self.alpha == other.alpha
    }

    /// `rgba(255,0,255,255)`. Decimal rather than hex because Beans has no
    /// hex formatting and a hand-rolled one in a value type is a second thing
    /// to get wrong.
    pub fn show() -> string {
        return "rgba({self.red},{self.green},{self.blue},{self.alpha})"
    }
}
