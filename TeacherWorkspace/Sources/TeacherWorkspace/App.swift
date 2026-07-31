import SwiftUI

@MainActor private var _snapshotState: AppState?

@main
struct TeacherWorkspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    init() {
        // Snapshot mode for automated UI verification:
        // TW_SNAPSHOT=<out.png> [TW_THEME=light] [TW_VIEW=rubrics|activities|pogs|integrations|welcome] [TW_PREVIEW=rubric|activity|pog]
        // The app launches normally, configures state, captures its own window
        // after the first frame, writes the PNG, and exits.
        let env = ProcessInfo.processInfo.environment
        guard env["TW_SNAPSHOT"] != nil else { return }
        MainActor.assumeIsolated {
            let snapState = AppState()
            if env["TW_THEME"] == "light" { snapState.themeName = "light" }
            switch env["TW_VIEW"] {
            case "rubrics": snapState.setView(.rubrics)
            case "activities": snapState.setView(.activities)
            case "pogs": snapState.setView(.pogs)
            case "integrations": snapState.setView(.integrations)
            case "welcome": snapState.newChat()
            default: break
            }
            switch env["TW_PREVIEW"] {
            case "rubric": snapState.openPreview(ArtifactRef(type: .rubric, id: "r1"))
            case "activity": snapState.openPreview(ArtifactRef(type: .activity, id: "a1"))
            case "pog": snapState.openPreview(ArtifactRef(type: .pog, id: "p2"))
            default: break
            }
            _snapshotState = snapState
        }
    }

    var body: some Scene {
        WindowGroup {
            let activeState = _snapshotState ?? state
            ContentView()
                .environmentObject(activeState)
                .frame(minWidth: 1100, minHeight: 640)
                .preferredColorScheme(activeState.theme.isDark ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Search Workspace") { state.toggleSearch() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New Chat") { state.newChat() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Toggle Preview Panel") { state.togglePreview() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running from a bare executable (swift run) needs an explicit
        // activation policy for the window to come to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let path = ProcessInfo.processInfo.environment["TW_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Self.captureWindow(to: path)
                exit(0)
            }
        }
    }

    /// Renders the app's own window content to a PNG — no screen-recording
    /// permission needed since it never reads other apps' pixels.
    @MainActor private static func captureWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let content = window.contentView else { return }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.layoutIfNeeded()
        content.displayIfNeeded()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
