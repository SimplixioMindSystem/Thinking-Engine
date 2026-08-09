//
//  Theme.swift
//  CortexOS
//
//  Single source of truth for all design tokens.
//  Calm. Focused. Premium. Dark-first.
//

import SwiftUI

// MARK: - Colors

enum CortexColor {
    // Backgrounds — adaptive dark-first
    static let bgPrimary   = Color(light: Color(white: 0.98), dark: Color(white: 0.07))
    static let bgSecondary = Color(light: Color(white: 0.94), dark: Color(white: 0.11))
    static let bgSurface   = Color(light: .white, dark: Color(white: 0.14))

    // Text
    static let textPrimary   = Color.primary
    static let textSecondary = Color(
        light: Color(white: 0.34),
        dark: Color(white: 0.72)
    )
    static let textTertiary = Color(
        light: Color(white: 0.44),
        dark: Color(white: 0.62)
    )

    // Accent — quiet blue-violet, not flashy
    static let accent    = Color(red: 0.38, green: 0.42, blue: 1.0) // #616BFF
    static let accentText = Color(
        light: Color(red: 0.28, green: 0.32, blue: 0.86),
        dark: Color(red: 0.62, green: 0.65, blue: 1.0)
    )
    static let accentDim = Color(red: 0.38, green: 0.42, blue: 1.0).opacity(0.15)
    static let accentForeground = Color.white
    static let strokeSubtle = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12))
    static let strokeStrong = Color(light: Color.black.opacity(0.16), dark: Color.white.opacity(0.24))

    // Semantic
    static let success = Color.green.opacity(0.85)
    static let warning = Color.orange.opacity(0.85)
    static let error   = Color.red.opacity(0.85)
    static let neutral = Color.gray.opacity(0.6)

    // Rank badges
    static func rank(_ position: Int) -> Color {
        switch position {
        case 1:  return accent
        case 2:  return Color(red: 0.45, green: 0.50, blue: 0.90)
        case 3:  return Color(red: 0.55, green: 0.58, blue: 0.78)
        default: return neutral
        }
    }

    /// Confidence-based color — subtle gradient from neutral to accent.
    static func confidence(_ value: Double) -> Color {
        let clamped = min(max(value, 0), 1)
        return Color(
            red:   0.38 + (1 - clamped) * 0.17,
            green: 0.42 + (1 - clamped) * 0.13,
            blue:  1.0  - (1 - clamped) * 0.22
        ).opacity(0.7 + clamped * 0.3)
    }
}

// MARK: - Color helpers

extension Color {
    /// Adaptive color for light/dark mode.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        self = dark
        #endif
    }
}

// MARK: - Typography

enum CortexFont {
    // Hierarchy
    static let largeTitle   = Font.system(.largeTitle, design: .default, weight: .bold)
    static let title        = Font.system(.title2, design: .default, weight: .semibold)
    static let headline     = Font.system(.headline, design: .default, weight: .semibold)
    static let bodyMedium   = Font.system(.body, design: .default, weight: .medium)
    static let body         = Font.system(.body, design: .default)
    static let caption      = Font.system(.caption, design: .default)
    static let captionMedium = Font.system(.caption, design: .default, weight: .medium)
    static let mono         = Font.system(.caption2, design: .monospaced)
}

// MARK: - Spacing (4-point grid)

enum CortexSpacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Radius

enum CortexRadius {
    static let small: CGFloat = 6
    static let card:  CGFloat = 10
    static let large: CGFloat = 16
}

enum CortexInput {
    static let singleLineMinHeight: CGFloat = 46
    static let multiLineMinHeight: CGFloat = 120
}

enum CortexControl {
    static let buttonMinHeight: CGFloat = 46
    static let chipButtonMinHeight: CGFloat = 34
    static let labelMinHeight: CGFloat = 22
}

// MARK: - Shadow modifier

struct CortexShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func cortexShadow() -> some View {
        modifier(CortexShadowModifier())
    }

    /// Unified input surface for text fields/editors across iOS/macOS.
    /// Keeps controls large, rounded, and visually consistent.
    func cortexInputSurface(minHeight: CGFloat = CortexInput.singleLineMinHeight) -> some View {
        self
            .font(CortexFont.body)
            .padding(.horizontal, CortexSpacing.md)
            .padding(.vertical, CortexSpacing.sm)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(CortexColor.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous))
            .cortexShadow()
    }

    /// Unified field label styling across forms/cards.
    func cortexFieldLabel() -> some View {
        self
            .font(CortexFont.captionMedium)
            .foregroundStyle(CortexColor.textSecondary)
            .frame(minHeight: CortexControl.labelMinHeight, alignment: .leading)
    }

    /// Shared card container used by macOS/iOS surfaces to keep spacing, stroke,
    /// and elevation consistent across settings, review, and creation screens.
    func cortexSurfaceCard(padding: CGFloat = CortexSpacing.lg) -> some View {
        self
            .padding(padding)
            .background(CortexColor.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: CortexRadius.card, style: .continuous)
                    .stroke(CortexColor.strokeSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CortexRadius.card, style: .continuous))
            .cortexShadow()
    }
}

// MARK: - Button styles

struct CortexPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CortexFont.bodyMedium)
            .foregroundStyle(CortexColor.accentForeground)
            .padding(.horizontal, CortexSpacing.md)
            .frame(minHeight: CortexControl.buttonMinHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                    .fill(CortexColor.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                    .stroke(CortexColor.accent.opacity(0.35), lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.42)
            .scaleEffect(isEnabled && configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }
}

struct CortexSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CortexFont.bodyMedium)
            .foregroundStyle(CortexColor.textPrimary)
            .padding(.horizontal, CortexSpacing.md)
            .frame(minHeight: CortexControl.buttonMinHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                    .fill(CortexColor.bgSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                    .stroke(CortexColor.strokeSubtle, lineWidth: 1)
            )
            .cortexShadow()
            .opacity(isEnabled ? (configuration.isPressed ? 0.94 : 1) : 0.42)
            .scaleEffect(isEnabled && configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }
}

struct CortexChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CortexFont.captionMedium)
            .foregroundStyle(prominent ? CortexColor.accent : CortexColor.textSecondary)
            .padding(.horizontal, CortexSpacing.md)
            .frame(minHeight: CortexControl.chipButtonMinHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? CortexColor.accentDim : CortexColor.bgSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(prominent ? CortexColor.accent.opacity(0.2) : CortexColor.strokeSubtle, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.42)
            .scaleEffect(isEnabled && configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }
}
