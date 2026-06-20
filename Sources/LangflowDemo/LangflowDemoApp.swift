import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct LangflowDemoApp: App {
    init() {
        // Bring the window to the foreground when launched via `swift run` on macOS.
        #if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup("LangflowKit Demo") {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
