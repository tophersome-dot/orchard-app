import SwiftUI
import UIKit

enum OrchardColor {
    static let grass = Color(red: 0.33, green: 0.78, blue: 0.22)
    static let grassDark = Color(red: 0.20, green: 0.62, blue: 0.14)
    static let grassDeep = Color(red: 0.12, green: 0.42, blue: 0.10)
    static let soil = Color(red: 0.62, green: 0.38, blue: 0.16)
    static let soilDark = Color(red: 0.42, green: 0.24, blue: 0.09)
    static let path = Color(red: 0.93, green: 0.76, blue: 0.42)
    static let pathEdge = Color(red: 0.76, green: 0.54, blue: 0.24)
    static let wood = Color(red: 0.67, green: 0.43, blue: 0.18)
    static let woodDark = Color(red: 0.46, green: 0.27, blue: 0.10)
    static let roof = Color(red: 0.16, green: 0.58, blue: 0.26)
    static let roofDark = Color(red: 0.08, green: 0.38, blue: 0.16)
    static let barn = Color(red: 0.89, green: 0.18, blue: 0.14)
    static let barnDark = Color(red: 0.62, green: 0.09, blue: 0.09)
    static let cream = Color(red: 1.0, green: 0.98, blue: 0.93)
    static let ink = Color(red: 0.09, green: 0.22, blue: 0.08)
    static let good = Color(red: 0.13, green: 0.66, blue: 0.22)
    static let mid = Color(red: 0.96, green: 0.62, blue: 0.05)
    static let bad = Color(red: 0.90, green: 0.18, blue: 0.16)
    static let leaf = Color(red: 0.18, green: 0.66, blue: 0.16)
    static let mint = Color(red: 0.96, green: 0.97, blue: 0.96)
    static let sun = Color(red: 1.0, green: 0.82, blue: 0.16)
    static let sky = Color(red: 0.22, green: 0.74, blue: 0.96)

    static func score(_ value: Double) -> Color {
        if value >= 4 { return good }
        if value >= 3 { return mid }
        return bad
    }
}

enum OrchardFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}

extension Color {
    init(hex: String, fallback: Color = Color(red: 0.7, green: 0.7, blue: 0.7)) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            self = fallback
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    func mixed(with other: Color, amount: CGFloat) -> Color {
        let start = UIColor(self)
        let end = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard start.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              end.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return self
        }
        let t = min(1, max(0, amount))
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }
}

struct OrchardCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func orchardCard() -> some View {
        modifier(OrchardCard())
    }
}
