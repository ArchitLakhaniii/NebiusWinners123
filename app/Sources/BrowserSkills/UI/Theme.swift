// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI

/// Clear desk tokens (design/concepts/clear-desk/DESIGN.md): one window material, tinted fills on it,
/// one ember accent used only for state and action, hairlines instead of dividers, status as words.
enum Theme {
    static let accent = adaptive(dark: "#e8784e", light: "#a93d17")
    static let accentFill = Color(hex: "#c4532a")
    static let control = adaptive(dark: "#ffffff", light: "#000000", darkAlpha: 0.08, lightAlpha: 0.06)
    static let control2 = adaptive(dark: "#ffffff", light: "#000000", darkAlpha: 0.13, lightAlpha: 0.11)
    static let hairline = adaptive(dark: "#ffffff", light: "#000000", darkAlpha: 0.10, lightAlpha: 0.09)
    static let page = Color(hex: "#fbfaf8")
    /// Window fill laid over the blurred material so the desk reads as one dark (or warm light) surface.
    static let window = adaptive(dark: "#1c1b1f", light: "#f3f0eb", darkAlpha: 0.78, lightAlpha: 0.84)
    static let sidebarWidth: CGFloat = 232
    static let panelWidth: CGFloat = 348
    static let inset: CGFloat = 10
    static let pageRadius: CGFloat = 10
    static let pillRadius: CGFloat = 9
    static let rowRadius: CGFloat = 7
    static let quick = Animation.easeOut(duration: 0.12)
    static let panelMotion = Animation.easeOut(duration: 0.18)

    static func adaptive(dark: String, light: String, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}

/// AppKit material behind the whole window. Behind-window blending lets the desktop tint through like Arc.
struct Material: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Section label: 12pt medium secondary, sentence case. No uppercase tracking.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// Primary action: white on the accent fill, 28pt.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.accentFill))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Secondary action: label on the control fill, 28pt, no border.
struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
            .padding(.horizontal, 12).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(configuration.isPressed ? Theme.control2 : Theme.control))
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Quiet text action beside a primary button.
struct PlainActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Sidebar and panel rows: 30pt tall, radius 7, filled only when active or hovered.
struct RowBackground: ViewModifier {
    var active: Bool
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(active ? Theme.control : (hover ? Theme.control.opacity(0.6) : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
            .onHover { h in withAnimation(Theme.quick) { hover = h } }
    }
}

extension View {
    func row(active: Bool = false) -> some View { modifier(RowBackground(active: active)) }
    func iconButton() -> some View { buttonStyle(.borderless).font(.system(size: 13, weight: .medium)) }
    func mono(_ size: CGFloat = 12) -> some View { font(.system(size: size, design: .monospaced)) }
}

/// Field on the control fill, radius 7 (inputs) or 9 (address pill).
struct FieldChrome: ViewModifier {
    var radius: CGFloat = Theme.rowRadius
    var height: CGFloat = 32
    func body(content: Content) -> some View {
        content.padding(.horizontal, 12).frame(height: height)
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.control))
    }
}

/// Keyboard shortcut hint next to a labeled control.
struct Shortcut: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(.tertiary) }
}
