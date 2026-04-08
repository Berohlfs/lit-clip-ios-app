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
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 3)
                        .frame(width: 72, height: 72)

                    Circle()
                        .fill(
                            session.isReachable
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.1, green: 0.6, blue: 0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(Color.white.opacity(0.1))
                        )
                        .frame(width: 60, height: 60)

                    if session.isSending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)

                            Text("SAVE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!session.isReachable || session.isSending)
            .opacity(session.isReachable ? 1.0 : 0.5)

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
