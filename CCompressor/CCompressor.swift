import SwiftUI
import AppKit

@main
struct CCompressor: App {
    init() {
        // Disable macOS automatic window tabs
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
        .commands {
            InspectorCommands()
        }
    }
}
