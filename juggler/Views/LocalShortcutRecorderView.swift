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
                NotificationCenter.default.post(name: .localShortcutsDidChange, object: nil)
            }
        }
        return field
    }

    func updateNSView(_ nsView: LocalShortcutRecorderField, context _: Context) {
        // Don't update while recording — the async binding update from onShortcutChange
        // can set stringValue on the field editor, triggering controlTextDidEndEditing
        // and prematurely stopping the recording session.
        guard !nsView.isRecording else { return }
        nsView.shortcut = shortcut
    }
}

/// NSSearchField subclass that captures keyboard shortcuts
final class LocalShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate {
    /// True when any recorder instance is actively capturing a shortcut
    static var isAnyRecording = false

    private let minimumWidth: CGFloat = 130
    private var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private(set) var isRecording = false
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

    deinit {
        endRecording()
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
        Self.isAnyRecording = true
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

    /// Clean up recording state without blurring focus.
    /// Callers that want to also lose focus should call blur() separately.
    /// This mirrors the KeyboardShortcuts library pattern where endRecording()
    /// is separate from blur() to prevent cascading stopRecording calls via
    /// controlTextDidEndEditing.
    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        Self.isAnyRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = "Record Shortcut"
        showsCancelButton = shortcut != nil
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidEndEditing(_: Notification) {
        // Just clean up recording state — don't blur, since we're already
        // losing focus (that's why this delegate fired).
        endRecording()
    }

    // Prevent typed characters from appearing — all input handled via event monitor
    func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                 replacementString _: String?) -> Bool
    {
        false
    }

    // Handle X button click — field stays first responder, so don't call
    // endRecording() here (it would tear down the event monitor with no
    // path to restart since becomeFirstResponder won't fire again).
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

        DispatchQueue.main.async { [weak self] in
            if let textView = self?.currentEditor() as? NSTextView {
                textView.insertionPointColor = .clear
                textView.delegate = self
            }
        }

        return true
    }

    // MARK: - NSTextViewDelegate

    func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            let clickPoint = convert(event.locationInWindow, from: nil)
            let clickMargin: CGFloat = 3.0
            if !bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint) {
                endRecording()
                blur()
                return event
            }
            return nil
        }

        guard event.type == .keyDown else { return event }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            blur()
            return nil
        }

        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            shortcut = nil
            onShortcutChange?(nil)
            updateDisplay()
            endRecording()
            blur()
            return nil
        }

        let newShortcut = LocalShortcut(keyCode: event.keyCode, modifiers: modifiers)
        shortcut = newShortcut
        onShortcutChange?(newShortcut)
        updateDisplay()
        endRecording()
        blur()
        return nil
    }
}
