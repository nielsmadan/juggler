## SwiftUI projects

Check the target platforms, deployment versions, SDK, and existing UI conventions before choosing
APIs. Use the project's build and test schemes; do not raise deployment targets or migrate its
observation or localization system as incidental cleanup.

Build controls with native interaction and accessibility semantics. Check keyboard operation,
accessible names, longer translations, supported text sizes, and constrained window sizes. Preserve
access to actions when navigation or toolbars adapt to the available space.

Use `review-swift` for Swift modeling, concurrency, ownership, SwiftUI state, identity, lifetime,
dependencies, and rendering cost. Use `review-swiftui` for accessibility, layout, navigation and
presentation, localization, and native interaction. `code-review` includes both when its scope
touches SwiftUI implementation. Keep findings within those boundaries. Trace normal user tasks
before edge cases, verify framework defaults before claiming a capability is missing, and separate
defects from optional UI polish.
