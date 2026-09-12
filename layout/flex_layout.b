// A run whose children share out the space that is left over.
package layout

/// A stack that grows and shrinks its children to fit.
///
/// Everything about measuring, margins, padding, justification and cross-axis
/// alignment is inherited from `StackLayout` unchanged. The one difference is
/// `distribute`: instead of giving each child the size it measured, free space
/// is handed out in proportion to `LayoutSpec.grow`, and overflow is taken
/// back in proportion to `LayoutSpec.shrink` weighted by each child's size.
///
/// ### Why this is a loop and not one division
///
/// Sharing space by weight is one line. Respecting each child's own minimum
/// and maximum while doing it is not: a child that hits a bound stops
/// absorbing its share, and the space it did not take has to go to the others,
/// which may push one of *them* into a bound. Dividing once and then clamping
/// looks right on a two-child example and quietly overflows the moment a
/// bound is involved.
///
/// So each round freezes the children that hit a bound and redistributes what
/// is left among the rest. At least one child freezes per round, or the round
/// changes nothing and the loop ends, so it runs at most once per child.
pub class FlexLayout extends StackLayout {
    pub fn init(axis: Direction, spacing: f64) {
        super.init(axis, spacing)
    }

    pub static fn row(spacing: f64) -> FlexLayout {
        return new FlexLayout(Direction.horizontal, spacing)
    }

    pub static fn column(spacing: f64) -> FlexLayout {
        return new FlexLayout(Direction.vertical, spacing)
    }

    pub override fn label() -> string {
        return "flex"
    }

    override fn shares_space() -> bool {
        return true
    }

    override fn distribute(run: AxisRun) {
        // Start from each child's base size, pulled inside its own bounds. A
        // child already out of range is frozen there: it has no slack to give
        // and no room to take.
        for index: int in 0..run.count {
            let base: f64 = run.base_at(index)
            let fitted: f64 = run.clamp_at(index, base)
            run.set_main(index, fitted)
            if fitted != base {
                run.freeze(index)
            }
        }

        for round: int in 0..(run.count + 1) {
            let slack: f64 = run.room - run.total()
            if slack > -0.0000001 && slack < 0.0000001 {
                return
            }
            let growing: bool = slack > 0.0
            var weight: f64 = 0.0
            for index: int in 0..run.count {
                if run.is_frozen(index) { continue }
                if growing {
                    weight = weight + run.grow_at(index)
                } else {
                    // Shrinking is weighted by size as well as by factor, so a
                    // wide child gives up more than a narrow one with the same
                    // factor. A narrow child would otherwise vanish first.
                    weight = weight + run.shrink_at(index) * run.main_at(index)
                }
            }
            if weight <= 0.0 {
                // Nobody left who is willing to move. The run overflows or
                // under-fills, and `justify` decides where the gap shows up.
                return
            }

            var froze: bool = false
            for index: int in 0..run.count {
                if run.is_frozen(index) { continue }
                var share: f64 = run.grow_at(index) / weight
                if !growing {
                    share = run.shrink_at(index) * run.main_at(index) / weight
                }
                let wanted: f64 = run.main_at(index) + slack * share
                let allowed: f64 = run.clamp_at(index, wanted)
                run.set_main(index, allowed)
                if allowed != wanted {
                    run.freeze(index)
                    froze = true
                }
            }
            if !froze {
                return
            }
        }
    }
}
