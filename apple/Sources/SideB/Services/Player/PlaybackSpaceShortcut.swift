import AppKit
import WebKit

/// Routes an unmodified Space key to playback while the app is active and text is not being edited.
@MainActor
final class PlaybackSpaceShortcut {
    private weak var player: PlayerViewModel?
    private nonisolated(unsafe) var eventMonitor: Any?

    func install(player: PlayerViewModel) {
        self.player = player
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window, window.isKeyWindow,
              let player, player.currentTrack != nil,
              Self.isPlainSpace(event),
              !Self.isEditingText(window.firstResponder) else {
            return event
        }

        // A held key sends repeats. Consume them without alternating playback repeatedly.
        if !event.isARepeat { player.togglePlayPause() }
        return nil
    }

    static func isPlainSpace(_ event: NSEvent) -> Bool {
        event.keyCode == 49 &&
        event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    static func isEditingText(_ responder: NSResponder?) -> Bool {
        switch responder {
        case let textView as NSTextView:
            return textView.isEditable
        case let textField as NSTextField:
            return textField.isEditable
        case is WKWebView:
            // The Google login page owns keyboard input inside its web content.
            return true
        default:
            return false
        }
    }
}
