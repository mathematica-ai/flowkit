import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct FlowDemoApp: App {
    init() {
        // Bring the window to the foreground when launched via `swift run` on macOS.
        #if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup("FlowKit Demo") {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
