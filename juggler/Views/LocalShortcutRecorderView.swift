//
//  LocalShortcutRecorderView.swift
//  Juggler
//
//  A SwiftUI view for recording local (in-app) keyboard shortcuts.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct LocalShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: LocalShortcut?
    let storageKey: String

    func makeNSView(context _: Context) -> LocalShortcutRecorderField {
        let field = LocalShortcutRecorderField()
        field.shortcut = shortcut
        field.onShortcutChange = { [storageKey] (newShortcut: LocalShortcut?) in
            DispatchQueue.main.async {
                shortcut = newShortcut
                if let newShortcut {
                    newShortcut.save(to: storageKey)
                } else {
                    LocalShortcut.remove(from: storageKey)
                }
            }
        }
        return field
    }

    func updateNSView(_ nsView: LocalShortcutRecorderField, context _: Context) {
        nsView.shortcut = shortcut
    }
}

/// NSSearchField subclass that captures keyboard shortcuts
final class LocalShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate {
    private let minimumWidth: CGFloat = 130
    private var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var isRecording = false
    private var canBecomeKey = false

    override var canBecomeKeyView: Bool { canBecomeKey }

    var shortcut: LocalShortcut? {
        didSet {
            updateDisplay()
        }
    }

    var onShortcutChange: ((LocalShortcut?) -> Void)?

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
    }

    override init(frame _: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        delegate = self
        placeholderString = "Record Shortcut"
        alignment = .center
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // Store cancel button for later use
        cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell

        updateDisplay()
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = minimumWidth
        return size
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        // Prevent receiving initial focus when the window appears
        // Enable after a brief delay so clicking still works
        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    private func updateDisplay() {
        if let shortcut {
            stringValue = shortcut.displayString
            showsCancelButton = true
        } else {
            stringValue = ""
            showsCancelButton = false
        }
    }

    private func startRecording() {
        isRecording = true
        placeholderString = "Press shortcut..."
        showsCancelButton = shortcut != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseUp,
            .rightMouseUp,
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = "Record Shortcut"
        showsCancelButton = shortcut != nil
        window?.makeFirstResponder(nil)
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidEndEditing(_: Notification) {
        stopRecording()
    }

    // Block ALL text changes
    func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                 replacementString _: String?) -> Bool
    {
        false
    }

    // Handle X button click
    func searchFieldDidEndSearching(_: NSSearchField) {
        shortcut = nil
        onShortcutChange?(nil)
        updateDisplay()
    }

    // MARK: - First Responder

    override func becomeFirstResponder() -> Bool {
        guard window != nil else { return false }

        let shouldBecomeFirstResponder = super.becomeFirstResponder()
        guard shouldBecomeFirstResponder else { return false }

        startRecording()

        // Hide caret
        DispatchQueue.main.async { [weak self] in
            if let textView = self?.currentEditor() as? NSTextView {
                textView.insertionPointColor = .clear
                textView.delegate = self
            }
        }

        return true
    }

    // MARK: - NSTextViewDelegate - Block text changes at this level too

    func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        // Handle mouse clicks outside the field
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            let clickPoint = convert(event.locationInWindow, from: nil)
            let clickMargin: CGFloat = 3.0
            if !bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint) {
                stopRecording()
                return event
            }
            return nil
        }

        guard event.type == .keyDown else { return event }

        // Normalize modifiers
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        // Tab without modifiers: move to next responder
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Tab) {
            stopRecording()
            return event
        }

        // Escape without modifiers: cancel recording
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return nil
        }

        // Delete/Backspace without modifiers: clear shortcut
        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            shortcut = nil
            onShortcutChange?(nil)
            updateDisplay()
            stopRecording()
            return nil
        }

        // Record the shortcut
        let newShortcut = LocalShortcut(keyCode: event.keyCode, modifiers: modifiers)
        shortcut = newShortcut
        onShortcutChange?(newShortcut)
        updateDisplay()
        stopRecording()
        return nil
    }
}
