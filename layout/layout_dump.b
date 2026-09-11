// The layout tree as text, for golden files.
package layout

import cortado.geometry

/// Prints a solved tree.
///
/// The companion to `widgets.WidgetDump`, and deliberately a different
/// formatter. That one truncates frames to whole points because it reads them
/// back off live platform objects, where sub-point differences come out of
/// font metrics that move between OS releases. This one prints the solver's
/// own arithmetic exactly, because a layout golden that hid a half point would
/// hide precisely the bugs this engine can have.
///
/// The format is one line per node:
///
/// ```
/// root stack frame=0,0,480,320
///   title leaf frame=16,16,240,20
/// ```
pub class LayoutDump {
    /// Every node in `root`, depth first, two spaces per level.
    pub static fn tree(root: LayoutNode) -> string {
        var out: string = ""
        write(root, 0, inout out)
        return out
    }

    /// One node, with no children and no trailing newline.
    pub static fn line(node: LayoutNode) -> string {
        return "{node.name} {node.layout().label()} frame={show(node.frame())}"
    }

    /// A rectangle printed exactly as the solver computed it.
    pub static fn rect(box: geometry.Rect) -> string {
        return show(box)
    }
}

fn write(node: LayoutNode, depth: int, inout out: string) {
    var indent: string = ""
    var level: int = 0
    for level: int in 0..depth {
        indent = "{indent}  "
    }
    out = "{out}{indent}{LayoutDump.line(node)}\n"
    for child: LayoutNode in node.children() {
        write(child, depth + 1, inout out)
    }
}

fn show(box: geometry.Rect) -> string {
    return "{box.x},{box.y},{box.width},{box.height}"
}
