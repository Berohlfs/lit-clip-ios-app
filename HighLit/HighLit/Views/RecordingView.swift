import SwiftUI

struct RecordingView: View {

    @State private var viewModel = RecordingViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Camera preview - full screen
            CameraPreviewView(session: viewModel.cameraService.session)
                .ignoresSafeArea()

            // Gradient overlay for readability
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .ignoresSafeArea()

            // Content overlay
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }
            .padding(.bottom, 50)

            // Save confirmation toast
            if viewModel.showSaveConfirmation {
                saveConfirmationToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            viewModel.startRecording()
        }
        .onDisappear {
            viewModel.stopRecording()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                viewModel.stopRecording()
            case .active:
                viewModel.startRecording()
            @unknown default:
                break
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showSaveConfirmation)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isSaveEnabled)
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if viewModel.state == .recording || viewModel.state == .saving {
                recordingIndicator
            }
            Spacer()
            if viewModel.state == .recording {
                cameraToggleButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var cameraToggleButton: some View {
        Button(action: viewModel.toggleCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.8), radius: 4)

            Text("REC")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            Text(viewModel.statusMessage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            saveButton
        }
        .padding(.horizontal, 24)
    }

    private var saveButton: some View {
        let progress = min(Double(viewModel.bufferSeconds) / 30.0, 1.0)

        return Button(action: viewModel.saveHighlight) {
            ZStack {
                // Background track ring
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 4)
                    .frame(width: 92, height: 92)

                // Progress ring — fills clockwise from top
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        viewModel.isBufferFull
                            ? AnyShapeStyle(LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: viewModel.bufferSeconds)

                // Glow when full
                if viewModel.isBufferFull {
                    Circle()
                        .stroke(.green.opacity(0.3), lineWidth: 8)
                        .frame(width: 92, height: 92)
                        .blur(radius: 6)
                }

                // Inner button fill
                Circle()
                    .fill(
                        viewModel.isSaveEnabled
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.1, green: 0.6, blue: 0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Color.white.opacity(0.1))
                    )
                    .frame(width: 76, height: 76)

                // Button content
                if viewModel.state == .saving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("SAVE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .disabled(!viewModel.isSaveEnabled || viewModel.state == .saving)
        .scaleEffect(viewModel.isSaveEnabled ? 1.0 : 0.9)
        .opacity(viewModel.isSaveEnabled ? 1.0 : 0.5)
    }

    // MARK: - Save Confirmation

    private var saveConfirmationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Highlight Saved!")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    if let clip = viewModel.savedClip {
                        Text("\(Int(clip.duration))s clip saved")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                Button {
                    viewModel.dismissSaveConfirmation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()
        }
    }
}

#Preview {
    RecordingView()
}
