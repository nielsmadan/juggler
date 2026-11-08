## Native macOS apps

The `macos` kit includes the shared SwiftUI guidance and both Swift review skills. Establish whether
this target is a native macOS app or Mac Catalyst before applying platform advice. Keep existing
AppKit integration where it supplies behavior SwiftUI does not provide.

Follow the app's scene and document model. Check menu commands and keyboard shortcuts against the
focused window and selection, including when no document is open. Preserve standard text editing
shortcuts, focus traversal, and default/cancel actions. Test two windows when the app supports them,
as well as closing and reopening its last window.

Check resizing, sidebar and inspector visibility, toolbar overflow, and Settings access where those
features exist. Match the app's minimum window size to usable content. For document apps, exercise
Open, Save, undo, and unsaved-change dismissal using the existing document flow.

Use `review-swiftui` for these interaction checks. The separate `macos-vm` kit is optional
machine-specific VM tooling; this kit requires no VM or additional MCP server.
