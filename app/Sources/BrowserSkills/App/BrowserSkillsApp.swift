// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI

@main
struct BrowserSkillsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("BrowserSkills") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") { model.newTab(url: model.homeURL) }.keyboardShortcut("t")
                Button("Close Tab") { if let t = model.selected { model.close(t) } }.keyboardShortcut("w")
                Button("Teach a Skill") { model.startTeaching() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button(model.panelVisible ? "Hide Panel" : "Show Panel") { model.panelVisible.toggle() }.keyboardShortcut("p", modifiers: [.command, .option])
                Button("Skills") { model.show(.skills) }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("Teach") { model.show(.teach) }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("Assistant") { model.show(.assistant) }.keyboardShortcut("j")
                Button("Settings") { model.show(.settings) }.keyboardShortcut(",")
                Divider()
                Button("Save Window Snapshot") { WindowSnapshot.save() }.keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { ParkingWindow.shared.order() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Writes a PNG of the main window to BROWSERSKILLS_SNAPSHOT_DIR (or ~/Pictures/BrowserSkills).
/// An app may capture its own windows without the screen recording permission.
enum WindowSnapshot {
    @discardableResult
    static func save() -> URL? {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.minX > -10000 && !($0 is NSPanel) }) else { return nil }
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let env = ProcessInfo.processInfo.environment["BROWSERSKILLS_SNAPSHOT_DIR"]
        let dir = env.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("BrowserSkills", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("snapshot-\(stamp).png")
        do { try png.write(to: url) } catch { return nil }
        return url
    }
}
