import WatchConnectivity

final class WatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityService()

    var onSaveRequested: (@MainActor () -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendResult(success: Bool) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["event": "saveResult", "success": success],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = message["command"] as? String, command == "save" else {
            replyHandler(["status": "error", "reason": "unknown_command"])
            return
        }
        Task { @MainActor in
            self.onSaveRequested?()
            replyHandler(["status": "received"])
        }
    }
}
