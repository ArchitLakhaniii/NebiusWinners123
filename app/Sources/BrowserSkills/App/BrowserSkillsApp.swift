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
                Button("Assistant") { model.show(.assistant) }.keyboardShortcut("j")
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
