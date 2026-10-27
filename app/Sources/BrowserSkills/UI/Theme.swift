// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI

/// Visual system: one accent, hairlines and translucent fills over system materials, no gradients.
enum Theme {
    static let accent = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let danger = Color(red: 0.94, green: 0.34, blue: 0.29)
    static let warning = Color(red: 0.88, green: 0.64, blue: 0.23)
    static let fill = Color.primary.opacity(0.06)
    static let fillStrong = Color.primary.opacity(0.10)
    static let hairline = Color.primary.opacity(0.08)
    static let sidebarWidth: CGFloat = 232
    static let panelWidth: CGFloat = 328
    static let inset: CGFloat = 10
    static let radius: CGFloat = 10
    static let rowRadius: CGFloat = 8
    static let quick = Animation.easeOut(duration: 0.15)
}

/// AppKit material behind the sidebar and panel. Behind-window blending lets the desktop tint through like Arc.
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

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.7).foregroundStyle(.tertiary)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// Secondary action: icon plus label on a tinted fill, no border.
struct PillButtonStyle: ButtonStyle {
    var primary = false
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 11.5 : 12.5, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .padding(.horizontal, small ? 9 : 12).padding(.vertical, small ? 5 : 7)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(primary ? Theme.accent : Theme.fillStrong))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Quiet text action, used next to a primary pill.
struct PlainActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Sidebar and panel rows: 30pt tall, radius 8, filled only when active or hovered.
struct RowBackground: ViewModifier {
    var active: Bool
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(active ? Theme.fillStrong : (hover ? Theme.fill : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
            .onHover { h in withAnimation(Theme.quick) { hover = h } }
    }
}

extension View {
    func row(active: Bool = false) -> some View { modifier(RowBackground(active: active)) }
    func iconButton() -> some View { buttonStyle(.borderless).font(.system(size: 13, weight: .medium)) }
}

/// Field look used in the sidebar address bar and panel inputs.
struct FieldChrome: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        content.padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(focused ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
    }
}
