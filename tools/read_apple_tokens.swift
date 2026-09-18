// Prints the iOS system colours and type scale behind render/theme.b.
// xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator \
//   tools/read_apple_tokens.swift -o /tmp/tokens && xcrun simctl spawn booted /tmp/tokens
import UIKit

func rgba(_ color: UIColor, _ traits: UITraitCollection) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "n/a" }
    return String(format: "0x%02x%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()),
                  Int((b * 255).rounded()), Int((a * 255).rounded()))
}

let colors: [(String, UIColor)] = [
    ("accent", .systemBlue), ("destructive", .systemRed), ("success", .systemGreen),
    ("warning", .systemOrange), ("foreground", .label), ("secondary_label", .secondaryLabel),
    ("tertiary_label", .tertiaryLabel), ("quaternary_label", .quaternaryLabel),
    ("background", .systemBackground), ("secondary_background", .secondarySystemBackground),
    ("tertiary_background", .tertiarySystemBackground), ("grouped_background", .systemGroupedBackground),
    ("card", .secondarySystemGroupedBackground), ("separator", .separator),
    ("opaque_separator", .opaqueSeparator), ("fill", .systemFill), ("secondary_fill", .secondarySystemFill),
    ("tertiary_fill", .tertiarySystemFill), ("quaternary_fill", .quaternarySystemFill),
    ("gray", .systemGray), ("gray2", .systemGray2), ("gray3", .systemGray3),
    ("gray4", .systemGray4), ("gray5", .systemGray5), ("gray6", .systemGray6),
]
let light = UITraitCollection(userInterfaceStyle: .light)
let dark = UITraitCollection(userInterfaceStyle: .dark)
for (name, color) in colors {
    print("pub fn \(name)() -> int { return self.pick(\(rgba(color, light)), \(rgba(color, dark))) }")
}

let styles: [(String, UIFont.TextStyle)] = [
    ("large_title", .largeTitle), ("title1", .title1), ("title2", .title2), ("title3", .title3),
    ("headline", .headline), ("body", .body), ("callout", .callout), ("subheadline", .subheadline),
    ("footnote", .footnote), ("caption1", .caption1), ("caption2", .caption2),
]
let regular = UITraitCollection(preferredContentSizeCategory: .large)
for (name, style) in styles {
    let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: regular)
    print("pub fn \(name)() -> f64 { return \(font.pointSize) }")
}

let button = UIButton(configuration: .filled())
button.setTitle("Button", for: .normal)
print("// button \(button.intrinsicContentSize), switch \(UISwitch().intrinsicContentSize), " +
      "slider \(UISlider().intrinsicContentSize), stepper \(UIStepper().intrinsicContentSize), " +
      "segmented \(UISegmentedControl(items: ["a", "b"]).intrinsicContentSize)")
