import AVFoundation
import UIKit

@preconcurrency
nonisolated final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    var onVideoSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    var onAudioSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.highlit.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.highlit.camera.videoOutput")
    private let audioOutputQueue = DispatchQueue(label: "com.highlit.camera.audioOutput")

    private(set) var videoFormatDescription: CMFormatDescription?
    private(set) var audioFormatDescription: CMFormatDescription?
    private(set) var videoTransform: CGAffineTransform = .identity
    private var isConfigured = false

    func requestAccessAndConfigure(completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else {
                completion(false)
                return
            }
            self.sessionQueue.async {
                self.setupSession()
                completion(true)
            }
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Private

    private func setupSession() {
        guard !isConfigured else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? audioSession.setActive(true)

        session.beginConfiguration()
        session.sessionPreset = .high

        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Video output — must discard late frames to prevent pipeline stalls
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Set video orientation to portrait and capture the transform
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            // Portrait rotation: 90 degrees clockwise
            videoTransform = CGAffineTransform(rotationAngle: .pi / 2)
        }

        // Audio output
        audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    // MARK: - Delegate

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === videoOutput {
            if videoFormatDescription == nil {
                videoFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
            }
            onVideoSampleBuffer?(sampleBuffer)
        } else if output === audioOutput {
            if audioFormatDescription == nil {
                audioFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
            }
            onAudioSampleBuffer?(sampleBuffer)
        }
    }
}
