import Foundation

enum ScriptInstaller {
    /// Runs a bundled shell script asynchronously.
    /// Returns nil on success, or an error message string on failure.
    static func runBundledScript(resource: String, type: String = "sh") async -> String? {
        guard let scriptPath = Bundle.main.path(forResource: resource, ofType: type) else {
            return "Install script not found in bundle"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Drain pipe on a non-cooperative thread to prevent buffer-full deadlock
        let readTask = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }

        // Set terminationHandler BEFORE run() — if the process exits instantly,
        // a handler set after run() can miss the event and hang the continuation.
        let exitStatus = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                try? pipe.fileHandleForReading.close()
                continuation.resume(returning: -1)
            }
        }

        let data = await readTask.value

        if exitStatus == 0 {
            return nil
        } else {
            let output = String(decoding: data, as: UTF8.self)
            return output.isEmpty ? "Process failed" : output
        }
    }

    static func installHooks() async -> String? {
        await runBundledScript(resource: "install")
    }

    static func installKittyWatcher() async -> String? {
        await runBundledScript(resource: "install_kitty_watcher")
    }
}
