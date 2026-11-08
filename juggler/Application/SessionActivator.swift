import Foundation

enum SessionActivationPolicy {
    case explicit
    case cycleEligible
    case automatic(SessionAutomaticActivation)
    case notification(SessionNotificationTarget)

    func resolve(_ requested: Session, in manager: SessionManager) -> Session? {
        guard let current = manager.sessions.first(where: { $0.id == requested.id }),
              current.agentSessionIdentity == requested.agentSessionIdentity else { return nil }
        switch self {
        case .explicit:
            return current
        case .cycleEligible:
            return current.isCycleEligible ? current : nil
        case let .automatic(request):
            guard manager.isValidAutomaticActivation(request), current.isCycleEligible,
                  current.automationToken == requested.automationToken else { return nil }
            return current
        case let .notification(target):
            guard target.sessionID == requested.id else { return nil }
            return manager.session(for: target)
        }
    }
}

enum SessionActivationError: Error {
    case invalidated
}

enum SessionActivationOutcome {
    case activated(Session)
    case unavailable
    case failed(any Error)
}

struct SessionActivationPresentation: Equatable {
    enum Success: Equatable {
        case none
        case sessionBeacon
        case onlySessionBeacon
    }

    enum Unavailable: Equatable {
        case none
        case activationFailed
        case beacon(String)
    }

    let success: Success
    let unavailable: Unavailable

    static let manual = Self(success: .none, unavailable: .activationFailed)
    static let cycle = Self(success: .sessionBeacon, unavailable: .beacon("All At Work"))
    static let onlySessionCycle = Self(success: .onlySessionBeacon, unavailable: .beacon("All At Work"))
    static let notificationJump = Self(success: .sessionBeacon, unavailable: .beacon("No Notification"))
    static let failureOnly = Self(success: .none, unavailable: .none)

    static func forCyclableCount(_ count: Int, returnsToFocusedSession: Bool) -> SessionActivationPresentation {
        count == 1 && returnsToFocusedSession ? .onlySessionCycle : .cycle
    }
}

@MainActor
final class SessionActivator {
    typealias BeaconPresenter = @MainActor (String, String?, String?, Bool) -> Void

    static let shared = SessionActivator()

    private let sessionManager: SessionManager
    private let registry: TerminalBridgeRegistry
    private let presentBeacon: BeaconPresenter
    private var activationInProgress = false
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    var queuedActivationCount: Int { activationWaiters.count }

    init(
        sessionManager: SessionManager = .shared,
        registry: TerminalBridgeRegistry = .shared,
        presentBeacon: @escaping BeaconPresenter = { title, note, metadata, force in
            BeaconManager.shared.show(sessionName: title, note: note, metadata: metadata, force: force)
        }
    ) {
        self.sessionManager = sessionManager
        self.registry = registry
        self.presentBeacon = presentBeacon
    }

    func activate(
        session: Session,
        trigger: ActivationTrigger,
        policy: SessionActivationPolicy,
        presentation: SessionActivationPresentation = .manual
    ) async -> SessionActivationOutcome {
        await waitForActivationTurn()
        defer { finishActivationTurn() }

        let attempt = await performActivation(session: session, trigger: trigger, policy: policy)
        present(attempt.outcome, using: presentation)
        return attempt.outcome
    }

    func activateFirstAvailable(
        trigger: ActivationTrigger,
        presentation: SessionActivationPresentation,
        automaticRequest: SessionAutomaticActivation? = nil,
        nextSession: () -> Session?
    ) async -> SessionActivationOutcome {
        await waitForActivationTurn()
        defer { finishActivationTurn() }

        var attemptedIDs: Set<String> = []
        while true {
            if let automaticRequest, !sessionManager.isValidAutomaticActivation(automaticRequest) {
                return .unavailable
            }
            guard let session = nextSession(), attemptedIDs.insert(session.id).inserted else { break }
            let policy: SessionActivationPolicy = automaticRequest.map { .automatic($0) } ?? .cycleEligible
            let attempt = await performActivation(session: session, trigger: trigger, policy: policy)
            if automaticRequest != nil, attempt.invalidated { return .unavailable }
            switch attempt.outcome {
            case .activated, .failed:
                present(attempt.outcome, using: presentation)
                return attempt.outcome
            case .unavailable:
                continue
            }
        }

        let outcome = SessionActivationOutcome.unavailable
        present(outcome, using: presentation)
        return outcome
    }

    private func waitForActivationTurn() async {
        guard activationInProgress else {
            activationInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            activationWaiters.append(continuation)
        }
    }

    private func finishActivationTurn() {
        guard !activationWaiters.isEmpty else {
            activationInProgress = false
            return
        }

        activationWaiters.removeFirst().resume()
    }

    private func performActivation(
        session: Session,
        trigger: ActivationTrigger,
        policy: SessionActivationPolicy
    ) async -> (outcome: SessionActivationOutcome, invalidated: Bool) {
        guard policy.resolve(session, in: sessionManager) != nil, !Task.isCancelled else {
            return (.unavailable, true)
        }
        var token: SessionManager.ActivationToken?
        defer {
            if let token { sessionManager.endActivation(token) }
        }

        do {
            let activated = try await TerminalActivation.activate(
                session: session,
                trigger: trigger,
                sessionManager: sessionManager,
                registry: registry,
                revalidate: { requested in
                    guard !Task.isCancelled, let current = policy.resolve(requested, in: self.sessionManager) else {
                        throw SessionActivationError.invalidated
                    }
                    if case let .automatic(request) = policy {
                        self.sessionManager.prepareAutomaticActivation(request, target: current)
                    }
                    token = self.sessionManager.beginActivation(targetSessionID: current.id)
                    return current
                }
            )
            if case let .automatic(request) = policy, let token {
                sessionManager.finishAutomaticActivation(request, target: activated, token: token)
            }
            return (.activated(activated), false)
        } catch SessionActivationError.invalidated {
            return (.unavailable, true)
        } catch TerminalBridgeError.sessionNotFound {
            return (.unavailable, false)
        } catch {
            return (.failed(error), false)
        }
    }

    private func present(
        _ outcome: SessionActivationOutcome,
        using presentation: SessionActivationPresentation
    ) {
        switch outcome {
        case let .activated(session):
            switch presentation.success {
            case .none:
                return
            case .sessionBeacon:
                let displayName = displayName(for: session)
                let metadata = BeaconMetadata.resolve(for: session, among: sessionManager.sessions)
                presentBeacon(displayName, session.note, metadata.subtitle, false)
            case .onlySessionBeacon:
                presentBeacon("Only 1 Session", session.note, displayName(for: session), false)
            }
        case .unavailable:
            switch presentation.unavailable {
            case .none:
                return
            case .activationFailed:
                presentBeacon("Activation Failed", nil, nil, true)
            case let .beacon(title):
                presentBeacon(title, nil, nil, false)
            }
        case .failed:
            presentBeacon("Activation Failed", nil, nil, true)
        }
    }

    private func displayName(for session: Session) -> String {
        let rawTitleMode = UserDefaults.standard.string(forKey: AppStorageKeys.sessionTitleMode) ?? ""
        let titleMode = SessionTitleMode(rawValue: rawTitleMode) ?? .default
        return sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode)
    }
}
