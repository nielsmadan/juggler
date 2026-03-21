import Foundation

enum ConfigFileWriter {
    enum DuplicateCheck {
        /// No duplicate checking
        case none
        /// Skip if the file contains the exact line
        case exactMatch
        /// Skip if a non-commented line starts with the same first word (directive key)
        case directiveKey
    }

    /// Appends a line to a config file, optionally creating parent directories.
    /// Returns nil on success, or an error description on failure.
    static func appendLine(
        _ line: String,
        toFileAt path: String,
        createDirectories: Bool = false,
        duplicateCheck: DuplicateCheck = .none
    ) -> String? {
        do {
            let fileURL = URL(fileURLWithPath: path)

            if createDirectories {
                let parentDir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            if FileManager.default.fileExists(atPath: path) {
                let existingContent = try String(contentsOfFile: path, encoding: .utf8)

                if isDuplicate(line: line, in: existingContent, check: duplicateCheck) {
                    return nil
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { handle.closeFile() }
                handle.seekToEndOfFile()

                var lineToAppend = line + "\n"
                if !existingContent.isEmpty, !existingContent.hasSuffix("\n") {
                    lineToAppend = "\n" + lineToAppend
                }

                handle.write(Data(lineToAppend.utf8))
            } else {
                try (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }

            return nil
        } catch {
            return "Failed to update \(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)"
        }
    }

    private static func isDuplicate(line: String, in contents: String, check: DuplicateCheck) -> Bool {
        switch check {
        case .none:
            return false
        case .exactMatch:
            return contents.contains(line)
        case .directiveKey:
            let directiveKey = String(line.split(separator: " ").first ?? "")
            return contents.split(separator: "\n").contains { l in
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("#") && trimmed.hasPrefix(directiveKey)
            }
        }
    }
}
