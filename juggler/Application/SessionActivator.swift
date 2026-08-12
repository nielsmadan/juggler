import Foundation

enum SessionActivationOutcome {
    case activated(Session)
    case unavailable
    case failed(any Error)
}

struct SessionActivationPresentation {
    enum Success {
        case none
        case sessionBeacon
    }

    enum Unavailable {
        case none
        case activationFailed
        case beacon(String)
    }

    let success: Success
    let unavailable: Unavailable

    static let manual = Self(success: .none, unavailable: .activationFailed)
    static let cycle = Self(success: .sessionBeacon, unavailable: .beacon("All At Work"))
    static let notificationJump = Self(success: .sessionBeacon, unavailable: .beacon("No Notification"))
    static let failureOnly = Self(success: .none, unavailable: .none)
}

@MainActor
final class SessionActivator {
    typealias BeaconPresenter = @MainActor (String, String?, Bool) -> Void

    static let shared = SessionActivator()

    private let sessionManager: SessionManager
    private let registry: TerminalBridgeRegistry
    private let presentBeacon: BeaconPresenter
    private var activationInProgress = false
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        sessionManager: SessionManager = .shared,
        registry: TerminalBridgeRegistry = .shared,
        presentBeacon: @escaping BeaconPresenter = { title, subtitle, force in
            BeaconManager.shared.show(sessionName: title, subtitle: subtitle, force: force)
        }
    ) {
        self.sessionManager = sessionManager
        self.registry = registry
        self.presentBeacon = presentBeacon
    }

    func activate(
        session: Session,
        trigger: ActivationTrigger,
        presentation: SessionActivationPresentation = .manual
    ) async -> SessionActivationOutcome {
        await waitForActivationTurn()
        defer { finishActivationTurn() }

        let outcome = await performActivation(session: session, trigger: trigger)
        present(outcome, using: presentation)
        return outcome
    }

    func activateFirstAvailable(
        trigger: ActivationTrigger,
        presentation: SessionActivationPresentation,
        nextSession: () -> Session?
    ) async -> SessionActivationOutcome {
        await waitForActivationTurn()
        defer { finishActivationTurn() }

        while let session = nextSession() {
            let outcome = await performActivation(session: session, trigger: trigger)
            switch outcome {
            case .activated, .failed:
                present(outcome, using: presentation)
                return outcome
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
        trigger: ActivationTrigger
    ) async -> SessionActivationOutcome {
        let token = sessionManager.beginActivation(targetSessionID: session.id)
        defer { sessionManager.endActivation(token) }

        do {
            try await TerminalActivation.activate(
                session: session,
                trigger: trigger,
                sessionManager: sessionManager,
                registry: registry
            )
            return .activated(session)
        } catch TerminalBridgeError.sessionNotFound {
            return .unavailable
        } catch {
            return .failed(error)
        }
    }

    private func present(
        _ outcome: SessionActivationOutcome,
        using presentation: SessionActivationPresentation
    ) {
        switch outcome {
        case let .activated(session):
            guard case .sessionBeacon = presentation.success else { return }
            let rawTitleMode = UserDefaults.standard.string(forKey: AppStorageKeys.sessionTitleMode) ?? ""
            let titleMode = SessionTitleMode(rawValue: rawTitleMode) ?? .default
            let displayName = sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode)
            let metadata = BeaconMetadata.resolve(for: session, among: sessionManager.sessions)
            presentBeacon(displayName, metadata.subtitle, false)
        case .unavailable:
            switch presentation.unavailable {
            case .none:
                return
            case .activationFailed:
                presentBeacon("Activation Failed", nil, true)
            case let .beacon(title):
                presentBeacon(title, nil, false)
            }
        case .failed:
            presentBeacon("Activation Failed", nil, true)
        }
    }
}
