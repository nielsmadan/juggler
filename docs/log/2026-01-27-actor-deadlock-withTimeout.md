# Actor Deadlock in withTimeout Task Group

**Date:** 2026-01-27
**Status:** Resolved
**Affected Area:** `juggler/Services/iTerm2Bridge.swift`, `juggler/Services/HookServer.swift`

## Problem
When a hook was received and `updateTerminalInfo()` called `ITerm2Bridge.shared.listSessions()`, the call would hang indefinitely - the method never executed. Sessions showed folder name instead of tab name because terminal info was never fetched.

## Symptoms
- Log showed `updateTerminalInfo: fetching for ...` but never `listSessions: ENTERED`
- `listSessions()` worked at startup but failed when called from HookServer
- No error messages - the call just hung silently
- Tab names never updated, sessions showed folder names only

## Root Cause
Actor deadlock caused by `withThrowingTaskGroup` inside an actor-isolated method.

The `listSessions()` method used a `withTimeout` helper:

```swift
// In ITerm2Bridge (actor)
func listSessions() async throws -> [TerminalSessionInfo] {
    response = try await withTimeout(listTimeout) {
        try await self.sendRequest(request)  // <-- Captures self
    }
}

private func withTimeout<T: Sendable>(...) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()  // Child task needs actor access
        }
        // ...
    }
}
```

**The deadlock mechanism:**
1. `HookServer.updateTerminalInfo()` calls `ITerm2Bridge.shared.listSessions()`
2. `listSessions()` is actor-isolated, acquires the ITerm2Bridge actor
3. `withTimeout()` creates a task group with `group.addTask { ... }`
4. The child task closure captures `self` and needs to hop onto the actor
5. But the parent task already holds the actor and is waiting for the child
6. Deadlock: parent waits for child, child waits for actor access

**Why it worked at startup:** Different call path without cross-actor contention.

## Solution
Removed the `withTimeout` wrapper from `listSessions()`. The socket already has a 1-second timeout configured in `sendRequest()`, making the wrapper redundant.

```swift
// Before (broken)
response = try await withTimeout(listTimeout) {
    try await self.sendRequest(request)
}

// After (fixed)
response = try await sendRequest(request)
```

Also removed unnecessary `Task.detached` wrapper from `HookServer.updateTerminalInfo()`.

## Investigation Notes
- Three parallel investigation agents all converged on the same root cause
- Git history showed the issue was introduced when `withTimeout` was added in the architecture redesign
- Swift actor isolation with `withThrowingTaskGroup` is a known footgun - child tasks that capture `self` can deadlock
- `Task.detached` didn't help because the deadlock was inside `ITerm2Bridge`, not in the cross-actor call

## Prevention
- Avoid using `withThrowingTaskGroup` inside actor-isolated methods when closures capture `self`
- If timeout is needed, use socket-level timeouts or `Task.sleep` with cancellation instead of task group racing
- When an actor method call hangs silently, suspect task group + actor isolation issues
- Add logging at method entry (before any `await`) to detect if methods are being entered

## Related
- Swift Evolution SE-0338: Clarify Execution of Non-Actor-Isolated Async Functions
- https://forums.swift.org/t/hang-when-awaiting-call-to-actor/54026
- Previous issue: docs/log/2026-01-26-terminal-info-not-updating.md (different root cause)
