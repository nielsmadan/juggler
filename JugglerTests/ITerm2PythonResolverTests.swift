import Foundation
@testable import Juggler
import Testing

@Suite("ITerm2PythonResolver")
struct ITerm2PythonResolverTests {
    @Test func prefersNewestModernUVRuntime() throws {
        let applicationSupport = try temporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let uvPython = try createUVPython(in: applicationSupport, version: "3.12", provisioned: true)
        _ = try createUVPython(in: applicationSupport, version: "3.9", provisioned: true)
        _ = try createPython(
            at: applicationSupport.appendingPathComponent("iterm2env-3.14.0/versions/3.14.0/bin/python3")
        )

        let result = ITerm2PythonResolver.resolve(applicationSupportDirectory: applicationSupport)

        #expect(result == uvPython.path)
    }

    @Test func skipsIncompleteUVRuntime() throws {
        let applicationSupport = try temporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        _ = try createUVPython(in: applicationSupport, version: "3.12", provisioned: false)
        let legacyPython = try createPython(
            at: applicationSupport.appendingPathComponent("iterm2env-3.10.19/versions/3.10.19/bin/python3")
        )

        let result = ITerm2PythonResolver.resolve(applicationSupportDirectory: applicationSupport)

        #expect(result == legacyPython.path)
    }

    @Test func findsVersionedLegacyRoot() throws {
        let applicationSupport = try temporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let versionedPython = try createPython(
            at: applicationSupport.appendingPathComponent("iterm2env-3.14.0/versions/3.14.0/bin/python3")
        )

        let result = ITerm2PythonResolver.resolve(applicationSupportDirectory: applicationSupport)

        #expect(result == versionedPython.path)
    }

    @Test func sortsLegacyVersionsNumerically() throws {
        let applicationSupport = try temporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        _ = try createPython(
            at: applicationSupport.appendingPathComponent("iterm2env/versions/3.8.19/bin/python3")
        )
        let newerPython = try createPython(
            at: applicationSupport.appendingPathComponent("iterm2env/versions/3.10.19/bin/python3")
        )

        let result = ITerm2PythonResolver.resolve(applicationSupportDirectory: applicationSupport)

        #expect(result == newerPython.path)
    }

    @Test func skipsNewerNonExecutableLegacyRuntime() throws {
        let applicationSupport = try temporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let incompletePython = applicationSupport
            .appendingPathComponent("iterm2env/versions/3.14.0/bin/python3")
        try FileManager.default.createDirectory(
            at: incompletePython.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: incompletePython)
        let executablePython = try createPython(
            at: applicationSupport.appendingPathComponent("iterm2env/versions/3.10.19/bin/python3")
        )

        let result = ITerm2PythonResolver.resolve(applicationSupportDirectory: applicationSupport)

        #expect(result == executablePython.path)
    }

    @Test func returnsNilWithoutExecutableRuntime() throws {
        let applicationSupport = try temporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let python = applicationSupport
            .appendingPathComponent("iterm2env-3.14.0/versions/3.14.0/bin/python3")
        try FileManager.default.createDirectory(
            at: python.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: python)

        let result = ITerm2PythonResolver.resolve(applicationSupportDirectory: applicationSupport)

        #expect(result == nil)
    }

    private func temporaryApplicationSupport() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-iterm2-python-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createUVPython(in applicationSupport: URL, version: String, provisioned: Bool) throws -> URL {
        let versionDirectory = applicationSupport.appendingPathComponent("uv/venvs/\(version)")
        if provisioned {
            try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
            try Data().write(to: versionDirectory.appendingPathComponent(".provisioned"))
        }
        return try createPython(at: versionDirectory.appendingPathComponent("bin/python"))
    }

    private func createPython(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
