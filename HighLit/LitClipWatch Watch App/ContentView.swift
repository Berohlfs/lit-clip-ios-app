import SwiftUI
import WatchConnectivity

struct ContentView: View {

    @State private var session = WatchSessionManager()

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isReachable ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(session.isReachable ? "Connected" : "Not connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(action: session.sendSave) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32))
                    Text("SAVE")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!session.isReachable || session.isSending)

            if session.isSending {
                ProgressView()
            }

            if let result = session.lastResult {
                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result ? .green : .red)
                    .font(.title3)
            }
        }
    }
}

@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {

    var isReachable = false
    var isSending = false
    var lastResult: Bool?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendSave() {
        guard WCSession.default.isReachable else { return }
        isSending = true
        lastResult = nil

        WCSession.default.sendMessage(
            ["command": "save"],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    if let status = reply["status"] as? String, status == "received" {
                        // Keep isSending true — wait for saveResult event
                    } else {
                        self.isSending = false
                        self.lastResult = false
                    }
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.isSending = false
                    self?.lastResult = false
                }
            }
        )
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let event = message["event"] as? String, event == "saveResult" else { return }
        let success = message["success"] as? Bool ?? false
        Task { @MainActor in
            self.isSending = false
            self.lastResult = success
            try? await Task.sleep(for: .seconds(3))
            self.lastResult = nil
        }
    }
}

#Preview {
    ContentView()
}
