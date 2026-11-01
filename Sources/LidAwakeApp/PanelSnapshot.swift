import AppKit
import SwiftUI

/// `LIDAWAKE_SNAPSHOT=panel.png [LIDAWAKE_SNAPSHOT_APPEARANCE=dark|light]` renders the panel to a PNG and exits.
/// Used for README screenshots without screen-recording permission.
@MainActor
enum PanelSnapshot {
    static func runIfRequested(model: AppModel) -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["LIDAWAKE_SNAPSHOT"] else { return false }
        let dark = env["LIDAWAKE_SNAPSHOT_APPEARANCE"] != "light"
        let view = PanelView()
            .environmentObject(model)
            .background(dark ? Color(white: 0.13) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)  // skip the quit confirmation
    }
}
