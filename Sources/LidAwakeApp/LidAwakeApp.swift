import AppKit
import LidAwakeCore
import SwiftUI

@main
struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(AppModel.shared)
        } label: {
            MenuBarLabel(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar icon: a laptop with a bolt while sleep is disabled, plus the time left when a timer runs.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.status.sleepDisabled {
            HStack(spacing: 3) {
                Image(systemName: "laptopcomputer.trianglebadge.exclamationmark")
                if let left = model.remaining { Text(Duration.format(left)) }
            }
        } else {
            Image(systemName: "laptopcomputer")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            AppModel.shared.start()
            _ = PanelSnapshot.runIfRequested(model: AppModel.shared)
        }
    }

    /// `lidawake://apply` (widget tap while the app was closed) applies the pending request.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls where url.scheme == WidgetBridge.urlScheme {
                if url.host == "settings" { SettingsWindow.open() } else { AppModel.shared.applyWidgetRequest() }
            }
        }
    }

    /// Nothing enforces the timer or battery floor once the app quits, so offer to turn sleep back on.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let model = AppModel.shared
            model.refresh()
            guard model.status.sleepDisabled else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = "Turn sleep back on before quitting?"
            alert.informativeText = "LidAwake is keeping the Mac awake with the lid closed. After quitting, nothing will turn it off automatically."
            alert.addButton(withTitle: "Turn Off and Quit")
            alert.addButton(withTitle: "Keep Awake and Quit")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                model.turnOff()
                return .terminateNow
            case .alertSecondButtonReturn:
                return .terminateNow
            default:
                return .terminateCancel
            }
        }
    }
}

/// The settings window, managed in AppKit. SwiftUI's Settings scene (and SettingsLink) does not reliably open
/// or come to the front in a menu-bar-only app, so the window is created and fronted here.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func open() {
        let window = self.window ?? make()
        self.window = window
        // Close the menu bar panel so it does not sit on top of the settings window.
        NSApp.windows.filter { $0.className.contains("MenuBarExtra") && $0.isVisible }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func make() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView().environmentObject(AppModel.shared))
        let window = NSWindow(contentViewController: host)
        window.title = "LidAwake Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(host.view.fittingSize)
        return window
    }
}
