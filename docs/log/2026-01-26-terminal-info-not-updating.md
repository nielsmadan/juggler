# Terminal Info Not Updating (Tab Names, Window Names)

**Date:** 2026-01-26
**Status:** Resolved
**Affected Area:** `Juggler/Services/ITerm2Bridge.swift`

## Problem
Sessions display folder name instead of tab name, and are grouped under "Unknown" instead of window title.

## Symptoms
- Session names show project folder name (e.g., "app") instead of iTerm2 tab name
- Sessions grouped under "Unknown" in main window instead of window title
- `[DEBUG] updateTerminalInfo error: dataCorrupted ... "Unexpected end of file"` in logs
- `Failed to sync with terminal: dataCorrupted` errors repeatedly

## Root Cause
Truncated socket reads in `ITerm2Bridge.swift`.

The `sendRequest` method was calling `recv()` only once and assuming it received the complete response. TCP is a stream protocol and doesn't guarantee complete messages in a single read - the daemon's JSON response was being truncated, causing JSON decode failures.

```swift
// BROKEN: Only reads once, may get partial response
var buffer = [CChar](repeating: 0, count: 65536)
let bytesRead = recv(sock, &buffer, buffer.count - 1, 0)
// If daemon sends more data than fits in one recv(), we get truncated JSON
```

## Solution
Read from socket in a loop until we receive a complete newline-terminated response:

```swift
// FIXED: Read in loop until complete response
var responseData = Data()
var buffer = [UInt8](repeating: 0, count: 4096)

while true {
    let bytesRead = recv(sock, &buffer, buffer.count, 0)
    if bytesRead <= 0 {
        break
    }
    responseData.append(contentsOf: buffer[0..<bytesRead])

    // Check if we've received a complete response (ends with newline)
    if let lastByte = responseData.last, lastByte == UInt8(ascii: "\n") {
        break
    }
}
```

## Investigation Notes
- Initial investigation incorrectly identified UUID format mismatch in HookServer.swift
- The UUID comparison fix was already in place but didn't solve the issue
- Console logs showed "dataCorrupted" and "Unexpected end of file" errors, pointing to truncated JSON
- The daemon sends newline-terminated JSON, so checking for trailing newline indicates complete response

## Prevention
- When reading from sockets, always handle the stream nature of TCP
- Don't assume a single `recv()` call returns complete data
- Use message framing (like newline termination) to detect complete messages
- Check for JSON decode errors specifically - "Unexpected end of file" usually means truncated data

## Related
- iterm2_daemon.py sends newline-terminated JSON responses
- ITerm2Bridge.swift `sendRequest()` handles all daemon communication
