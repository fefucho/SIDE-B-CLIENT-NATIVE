import AppKit
import SwiftUI

/// Allows the window's content to extend behind its native titlebar controls.
struct WindowConfigurator: NSViewRepresentable {
    let isFullscreenPresented: Bool

    func makeNSView(context: Context) -> WindowConfigurationView {
        try? "makeNSView".write(toFile: "/tmp/sideb-titlebar-diagnostic.txt", atomically: true, encoding: .utf8)
        return WindowConfigurationView()
    }

    func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
        nsView.setFullscreenPresented(isFullscreenPresented)
    }
}

final class WindowConfigurationView: NSView {
    private var configurationPending = false
    private var wasFullscreenPresented: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        try? "viewDidMoveToWindow window=\(String(describing: window))".write(toFile: "/tmp/sideb-titlebar-diagnostic.txt", atomically: true, encoding: .utf8)
        scheduleConfiguration()
    }

    func setFullscreenPresented(_ isFullscreenPresented: Bool) {
        guard wasFullscreenPresented != isFullscreenPresented else { return }
        wasFullscreenPresented = isFullscreenPresented
        scheduleConfiguration()
    }

    private func scheduleConfiguration() {
        guard window != nil, !configurationPending else { return }

        configurationPending = true
        // SwiftUI applies its scene style after attaching this view. Configure
        // the titlebar once that initial window setup has completed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            self.configurationPending = false
            try? "configuration window=\(String(describing: self.window))".write(toFile: "/tmp/sideb-titlebar-diagnostic.txt", atomically: true, encoding: .utf8)
            guard let window = self.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "SideBWindowToolbar")
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
                window.toolbarStyle = .unified
            }
            if let button = window.standardWindowButton(.closeButton) {
                var view: NSView? = button
                var lines: [String] = []
                while let current = view {
                    lines.append("\(type(of: current)) frame=\(current.frame) bounds=\(current.bounds) flipped=\(current.isFlipped)")
                    view = current.superview
                }
                try? lines.joined(separator: "\n").write(toFile: "/tmp/sideb-titlebar-diagnostic.txt", atomically: true, encoding: .utf8)
            } else {
                try? "no close button".write(toFile: "/tmp/sideb-titlebar-diagnostic.txt", atomically: true, encoding: .utf8)
            }
        }
    }
}
