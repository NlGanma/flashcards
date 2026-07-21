import SwiftUI
import AppKit

@main
struct VocabFlashcardsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("Vocab Flashcards") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 880, minHeight: 640)
                .onAppear { app.bootstrap() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)
        .commands {
            // Replace the default "New" with "Open File…".
            CommandGroup(replacing: .newItem) {
                Button("Open File…") { app.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Known Words…") { app.showWordManager(.known) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Almost Known…") { app.showWordManager(.aside) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
            }
        }
    }
}

/// Ensures the SPM-built executable behaves as a normal foreground app: shows in the
/// Dock, takes focus on launch, and quits when its window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Parser diagnostics mode.
        if let path = ProcessInfo.processInfo.environment["VF_PARSE"] {
            ParseDebug.run(path: path)
            exit(0)
        }
        // Offscreen snapshot mode (for visual verification); exits when done.
        if SnapshotRenderer.runIfRequested() {
            exit(0)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
