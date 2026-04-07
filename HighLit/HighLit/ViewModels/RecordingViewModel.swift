import AVFoundation
import Observation
import Photos
import SwiftUI

@Observable
final class RecordingViewModel {

    enum RecordingState {
        case idle
        case recording
        case saving
    }

    private(set) var state: RecordingState = .idle
    private(set) var bufferSeconds: Int = 0
    private(set) var isBufferFull: Bool = false
    private(set) var savedClip: VideoClip?
    private(set) var errorMessage: String?
    private(set) var showSaveConfirmation: Bool = false
    private(set) var cameraPermissionDenied: Bool = false

    var isSaveEnabled: Bool {
        state == .recording && bufferSeconds > 0
    }

    var statusMessage: String {
        if state == .saving {
            return "Saving highlight..."
        }
        if isBufferFull {
            return "30s ready to export"
        }
        if bufferSeconds > 0 {
            return "\(bufferSeconds)s ready to export"
        }
        return "Starting..."
    }

    let cameraService = CameraService()
    private let bufferManager = VideoBufferManager(bufferDuration: 30.0)
    private var progressTimer: Timer?

    func startRecording() {
        guard state == .idle else { return }

        cameraService.onVideoSampleBuffer = { [weak self] sampleBuffer in
            self?.bufferManager.appendVideoSample(sampleBuffer)
        }
        cameraService.onAudioSampleBuffer = { [weak self] sampleBuffer in
            self?.bufferManager.appendAudioSample(sampleBuffer)
        }

        cameraService.requestAccessAndConfigure { [weak self] granted in
            guard let self else { return }
            Task { @MainActor [self] in
                guard granted else {
                    self.cameraPermissionDenied = true
                    return
                }
                self.bufferManager.videoTransform = self.cameraService.videoTransform
                self.bufferManager.start()
                self.cameraService.start()
                self.state = .recording
                self.errorMessage = nil
                self.showSaveConfirmation = false
                self.startProgressUpdates()
            }
        }
    }

    func stopRecording() {
        cameraService.stop()
        stopProgressUpdates()
        bufferManager.flush()
        state = .idle
        bufferSeconds = 0
        isBufferFull = false
    }

    func saveHighlight() {
        guard isSaveEnabled else { return }

        state = .saving

        Task {
            do {
                let url = try await bufferManager.saveBuffer()
                let duration = bufferManager.currentDuration

                // Save to Camera Roll
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: url)

                await MainActor.run {
                    self.savedClip = VideoClip(url: url, duration: duration)
                    self.showSaveConfirmation = true
                    self.state = .recording
                    dismissConfirmationAfterDelay()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.state = .recording
                }
            }
        }
    }

    func dismissSaveConfirmation() {
        showSaveConfirmation = false
    }

    // MARK: - Private

    private func startProgressUpdates() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let duration = self.bufferManager.recordingDuration
            let seconds = min(Int(duration), Int(self.bufferManager.bufferDuration))
            let full = self.bufferManager.isBufferFull
            Task { @MainActor in
                self.bufferSeconds = seconds
                self.isBufferFull = full
            }
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func dismissConfirmationAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                self.showSaveConfirmation = false
            }
        }
    }
}
