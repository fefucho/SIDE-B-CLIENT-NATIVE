import AppKit
import Testing
@testable import SideB

@Test @MainActor func spaceShortcutRespectsEditableFocus() {
    let editor = NSTextView()
    editor.isEditable = true
    #expect(PlaybackSpaceShortcut.isEditingText(editor))

    editor.isEditable = false
    #expect(!PlaybackSpaceShortcut.isEditingText(editor))

    let field = NSTextField()
    field.isEditable = true
    #expect(PlaybackSpaceShortcut.isEditingText(field))

    field.isEditable = false
    #expect(!PlaybackSpaceShortcut.isEditingText(field))
    #expect(!PlaybackSpaceShortcut.isEditingText(NSButton()))
}

@Test @MainActor func spaceShortcutIgnoresModifiedKeys() throws {
    func event(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: keyCode
        ))
    }

    #expect(PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49, modifiers: .command)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49, modifiers: .option)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 49, modifiers: .shift)))
    #expect(!PlaybackSpaceShortcut.isPlainSpace(try event(keyCode: 36)))
}
