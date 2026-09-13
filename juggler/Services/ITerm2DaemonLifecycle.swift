import Foundation

actor ITerm2DaemonLifecycle {
    nonisolated enum Operation: Sendable {
        case start
        case restart
        case stop
        case update

        var launchesDaemon: Bool { self == .start || self == .restart }
    }

    private var pending: [(id: UUID, operation: Operation, task: Task<Void, Error>)] = []
    private var processID: ObjectIdentifier?

    func enqueue(_ operation: Operation, action: @escaping @Sendable () async throws -> Void) -> Task<Void, Error> {
        if let previous = pending.last(where: { $0.operation != .update }) {
            if operation.launchesDaemon, previous.operation.launchesDaemon {
                return previous.task
            }
            if operation == .stop, previous.operation == .stop {
                return previous.task
            }
        }
        if operation == .stop {
            for item in pending where item.operation.launchesDaemon {
                item.task.cancel()
            }
        }

        let previous = pending.last?.task
        let id = UUID()
        let task = Task {
            defer { pending.removeAll { $0.id == id } }
            _ = try? await previous?.value
            try Task.checkCancellation()
            try await action()
        }
        pending.append((id, operation, task))
        return task
    }

    func trackProcess(_ process: Process?) {
        processID = process.map(ObjectIdentifier.init)
    }

    func exited(_ process: Process, action: @escaping @Sendable () async -> Void) async {
        let task = enqueue(.update) {
            await self.applyExit(process, action: action)
        }
        _ = try? await task.value
    }

    private func applyExit(_ process: Process, action: @Sendable () async -> Void) async {
        guard processID == ObjectIdentifier(process) else { return }
        await action()
    }
}
