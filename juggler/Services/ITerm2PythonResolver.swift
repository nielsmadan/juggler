import Foundation

nonisolated enum ITerm2PythonResolver {
    private struct Candidate {
        let version: [Int]
        let path: String
    }

    static func resolve(
        applicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let uvCandidates = candidates(
            in: applicationSupportDirectory.appendingPathComponent("uv/venvs"),
            executableNames: ["python", "python3"],
            requiredMarker: ".provisioned",
            fileManager: fileManager
        )
        if let candidate = newest(uvCandidates) {
            return candidate.path
        }

        let rootNames = (try? fileManager.contentsOfDirectory(atPath: applicationSupportDirectory.path)) ?? []
        let legacyRoots = ["iterm2env"] + rootNames.filter { $0.hasPrefix("iterm2env-") }
        let legacyCandidates = legacyRoots.flatMap { rootName in
            candidates(
                in: applicationSupportDirectory
                    .appendingPathComponent(rootName)
                    .appendingPathComponent("versions"),
                executableNames: ["python3", "python"],
                requiredMarker: nil,
                fileManager: fileManager
            )
        }
        return newest(legacyCandidates)?.path
    }

    private static func candidates(
        in versionsDirectory: URL,
        executableNames: [String],
        requiredMarker: String?,
        fileManager: FileManager
    ) -> [Candidate] {
        let versionNames = (try? fileManager.contentsOfDirectory(atPath: versionsDirectory.path)) ?? []
        return versionNames.compactMap { versionName in
            guard let version = numericVersion(versionName) else { return nil }
            let versionDirectory = versionsDirectory.appendingPathComponent(versionName)
            if let requiredMarker,
               !fileManager.fileExists(atPath: versionDirectory.appendingPathComponent(requiredMarker).path) {
                return nil
            }
            for executableName in executableNames {
                let path = versionDirectory
                    .appendingPathComponent("bin")
                    .appendingPathComponent(executableName)
                    .path
                if fileManager.isExecutableFile(atPath: path) {
                    return Candidate(version: version, path: path)
                }
            }
            return nil
        }
    }

    private static func numericVersion(_ value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }
        let numbers = components.compactMap { Int($0) }
        return numbers.count == components.count ? numbers : nil
    }

    private static func newest(_ candidates: [Candidate]) -> Candidate? {
        candidates.max { lhs, rhs in
            switch compare(lhs.version, rhs.version) {
            case .orderedAscending:
                true
            case .orderedDescending:
                false
            case .orderedSame:
                lhs.path < rhs.path
            }
        }
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0 ..< max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }
}
