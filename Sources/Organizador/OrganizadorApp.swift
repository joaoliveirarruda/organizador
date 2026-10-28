import AppKit
import OrganizadorCore
import SwiftUI

@main
struct OrganizadorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Organizador", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without an app bundle (`swift run`), macOS would start the app in the background.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
