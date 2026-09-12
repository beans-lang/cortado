// One named value on a described widget.
package component

import cortado.host
import cortado.widgets

/// A property a component asked for, as a value that can be compared.
///
/// The whole point of this type is the comparison. A render produces a
/// description of what the interface should look like; the differ compares it
/// with the last description and asks the platform to change only what
/// actually changed. That comparison has to be exact and cheap, which is why
/// an attribute is a struct of plain fields keyed by the host's own property
/// id rather than a name looked up in a map.
///
/// `property` is a `host.P_*` constant, so the applier is a three-way switch
/// over `ctd_set_int`, `ctd_set_real` and `ctd_set_text` and not a table of
/// strings. Markup speaks names; `Builder` translates them once, here, and
/// everything downstream is integers.
pub struct Attribute {
    pub property: int = 0
    pub kind: AttributeKind = AttributeKind.flag
    pub text: string = ""
    pub number: f64 = 0.0
    pub whole: int = 0

    /// A widget's text. It carries no property id because the ABI gives text
    /// its own pair of entry points rather than a slot in the property table.
    pub static fn of_text(value: string) -> Attribute {
        return Attribute { property: 0, kind: AttributeKind.text, text: value }
    }

    pub static fn of_whole(property: int, value: int) -> Attribute {
        return Attribute { property: property, kind: AttributeKind.whole, whole: value }
    }

    pub static fn of_real(property: int, value: f64) -> Attribute {
        return Attribute { property: property, kind: AttributeKind.real, number: value }
    }

    pub static fn of_flag(property: int, value: bool) -> Attribute {
        return Attribute { property: property, kind: AttributeKind.flag,
                           whole: if value { 1 } else { 0 } }
    }

    pub fn is_on() -> bool {
        return self.whole != 0
    }

    /// Whether two attributes describe the same property with the same value.
    ///
    /// Only the field the kind actually uses is compared. An attribute built
    /// as a flag carries a zero `number`, and comparing that too would make
    /// every attribute unequal to itself the moment a constructor changed.
    pub fn same_as(other: Attribute) -> bool {
        if self.property != other.property || self.kind != other.kind {
            return false
        }
        match self.kind {
            text => { return self.text == other.text }
            real => { return self.number == other.number }
            whole => { return self.whole == other.whole }
            flag => { return self.whole == other.whole }
        }
    }

    /// What to write when a property the last render set is gone from this
    /// one.
    ///
    /// A property that disappears has to be *reset*, not left alone. An author
    /// who deletes `disabled` from their markup means the control should be
    /// enabled again, and a framework that only ever set properties would
    /// leave it disabled for the life of the window with nothing to explain
    /// why. The defaults below are the platform's, which is what a freshly
    /// created widget of that kind already has.
    pub static fn default_for(property: int, kind: AttributeKind) -> Attribute {
        if kind == AttributeKind.text {
            return Attribute.of_text("")
        }
        if property == host.P_ENABLED || property == host.P_EDITABLE {
            return Attribute.of_flag(property, true)
        }
        if kind == AttributeKind.flag {
            return Attribute.of_flag(property, false)
        }
        if kind == AttributeKind.real {
            return Attribute.of_real(property, 0.0)
        }
        return Attribute.of_whole(property, 0)
    }

    /// The attribute as a golden file prints it: `enabled=false`, `text="Buy"`.
    pub fn show() -> string {
        match self.kind {
            text => { return "text=\"{self.text}\"" }
            real => { return "{property_name(self.property)}={self.number}" }
            whole => {
                // A packed colour is the one whole number a reader cannot
                // read. These goldens exist to be read by people, and
                // `color=4278190335` says nothing that `rgba(255,0,0,255)`
                // does not say better.
                if self.property == host.P_COLOR {
                    return "color={widgets.ColorWell.unpack(self.whole).show()}"
                }
                return "{property_name(self.property)}={self.whole}"
            }
            flag => { return "{property_name(self.property)}={self.is_on()}" }
        }
    }
}

/// The readable name of a host property id.
///
/// Goldens are read by people. An unknown id prints as a number rather than as
/// a guess, so adding a property to the header and forgetting this function
/// shows up as `p12=3` in a test rather than as the wrong name.
pub fn property_name(property: int) -> string {
    if property == host.P_CHECKED { return "checked" }
    if property == host.P_ENABLED { return "enabled" }
    if property == host.P_HIDDEN { return "hidden" }
    if property == host.P_MIN { return "min" }
    if property == host.P_MAX { return "max" }
    if property == host.P_VALUE { return "value" }
    if property == host.P_EDITABLE { return "editable" }
    if property == host.P_ALIGNMENT { return "alignment" }
    if property == host.P_FONT_SIZE { return "font_size" }
    if property == host.P_STEP { return "step" }
    if property == host.P_SELECTED { return "selected" }
    if property == host.P_INDETERMINATE { return "indeterminate" }
    if property == host.P_OPACITY { return "opacity" }
    if property == host.P_ANIMATING { return "animating" }
    if property == host.P_DATE { return "day" }
    if property == host.P_COLOR { return "color" }
    if property == host.P_EXPANDED { return "open" }
    return "p{property}"
}
