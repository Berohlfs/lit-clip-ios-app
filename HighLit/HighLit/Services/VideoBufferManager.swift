import AVFoundation
import CoreMedia
import UIKit

enum ExportOrientation {
    case portrait
    case landscape

    func preferredTransform(sourceWidth: CGFloat, sourceHeight: CGFloat) -> CGAffineTransform {
        switch self {
        case .portrait:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: sourceHeight, ty: 0)
        case .landscape:
            return .identity
        }
    }
}

nonisolated final class VideoBufferManager: @unchecked Sendable {

    nonisolated let bufferDuration: TimeInterval

    private let segmentDuration: TimeInterval = 60.0
    private let lock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.highlit.buffer.writer")

    // Completed segment files (rolling window)
    private var segments: [SegmentInfo] = []

    // Current segment being written
    private var currentWriter: AVAssetWriter?
    private var currentVideoInput: AVAssetWriterInput?
    private var currentAudioInput: AVAssetWriterInput?
    private var currentSegmentURL: URL?
    private var currentSegmentStartTime: CMTime = .invalid
    private var sessionStartTime: Date?
    private var hasStartedSession = false
    private var videoFormatDescription: CMFormatDescription?

    // Old writer finishing asynchronously during rotation
    private var pendingWriter: AVAssetWriter?
    private var pendingURL: URL?

    // Protects segments from pruning during export
    private var isSaving = false

    init(bufferDuration: TimeInterval = 30.0) {
        self.bufferDuration = bufferDuration
    }

    var recordingDuration: TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var currentDuration: TimeInterval {
        min(recordingDuration, bufferDuration)
    }

    var isBufferFull: Bool {
        recordingDuration >= bufferDuration
    }

    func start() {
        lock.lock()
        sessionStartTime = Date()
        lock.unlock()
    }

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.sync {
            if videoFormatDescription == nil {
                videoFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if currentWriter == nil {
                startNewSegment(at: pts)
            }

            if hasStartedSession,
               currentSegmentStartTime.isValid,
               CMTimeGetSeconds(pts - currentSegmentStartTime) >= segmentDuration {
                rotateSegment(at: pts)
            }

            guard let writer = currentWriter,
                  let videoInput = currentVideoInput,
                  writer.status == .writing else { return }

            if !hasStartedSession {
                writer.startSession(atSourceTime: pts)
                currentSegmentStartTime = pts
                hasStartedSession = true
            }

            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        }
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.sync {
            guard let audioInput = currentAudioInput,
                  let writer = currentWriter,
                  writer.status == .writing,
                  hasStartedSession,
                  audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        }
    }

    func flush() {
        writerQueue.sync {
            waitForPendingWriter()
            finishCurrentSegmentBlocking()
            deleteAllSegmentFiles()
            sessionStartTime = nil
            videoFormatDescription = nil
        }
    }

    func saveBuffer(orientation: ExportOrientation) async throws -> URL {
        let segmentURLs: [URL] = writerQueue.sync {
            // Wait for any pending rotation to complete before snapshotting
            waitForPendingWriter()
            finishCurrentSegmentBlocking()
            isSaving = true
            lock.lock()
            let urls = segments.map(\.url)
            lock.unlock()
            return urls
        }

        defer {
            writerQueue.sync {
                isSaving = false
                pruneOldSegments()
            }
        }

        guard !segmentURLs.isEmpty else {
            throw BufferError.emptyBuffer
        }

        // Compose segments into a single output
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw BufferError.compositionFailed
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var insertTime = CMTime.zero

        for url in segmentURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let assetVideoTrack = videoTracks.first {
                try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: insertTime)
            }
            if let assetAudioTrack = audioTracks.first, let audioTrack {
                try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: insertTime)
            }

            insertTime = insertTime + duration
        }

        // Apply orientation as metadata
        let trackSize = try await videoTrack.load(.naturalSize)
        videoTrack.preferredTransform = orientation.preferredTransform(
            sourceWidth: trackSize.width,
            sourceHeight: trackSize.height
        )

        // Trim to last bufferDuration
        let totalDuration = insertTime
        let maxDuration = CMTimeMakeWithSeconds(bufferDuration, preferredTimescale: 600)

        let outputURL = makeClipURL()

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw BufferError.exportFailed
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        if totalDuration > maxDuration {
            let trimStart = totalDuration - maxDuration
            exportSession.timeRange = CMTimeRange(start: trimStart, duration: maxDuration)
        }

        await exportSession.export()

        if let error = exportSession.error {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw BufferError.exportFailed
        }

        return outputURL
    }

    // MARK: - Segment Rotation (non-blocking)

    private func rotateSegment(at time: CMTime) {
        // Wait for any previous pending rotation first
        waitForPendingWriter()

        // Capture old writer references
        let oldWriter = currentWriter
        let oldVideoInput = currentVideoInput
        let oldAudioInput = currentAudioInput
        let oldURL = currentSegmentURL

        // Start new writer IMMEDIATELY — no frame gap
        currentWriter = nil
        currentVideoInput = nil
        currentAudioInput = nil
        currentSegmentURL = nil
        currentSegmentStartTime = .invalid
        hasStartedSession = false
        startNewSegment(at: time)

        // Finish old writer asynchronously
        guard let oldWriter, let oldURL else { return }

        oldVideoInput?.markAsFinished()
        oldAudioInput?.markAsFinished()

        pendingWriter = oldWriter
        pendingURL = oldURL

        oldWriter.finishWriting { [weak self] in
            self?.writerQueue.async {
                self?.completePendingWriter()
            }
        }

        pruneOldSegments()
    }

    private func completePendingWriter() {
        guard let writer = pendingWriter, let url = pendingURL else { return }

        if writer.status == .completed {
            lock.lock()
            segments.append(SegmentInfo(url: url, createdAt: Date()))
            lock.unlock()
        } else {
            try? FileManager.default.removeItem(at: url)
        }

        pendingWriter = nil
        pendingURL = nil
    }

    private func waitForPendingWriter() {
        guard pendingWriter != nil else { return }

        // finishWriting was already called during rotation.
        // Poll until the writer transitions out of .writing state.
        // This happens on AVAssetWriter's internal queue (~50-100ms).
        while pendingWriter?.status == .writing {
            Thread.sleep(forTimeInterval: 0.005)
        }

        // Complete inline. The queued writerQueue.async callback from
        // rotateSegment will find pendingWriter == nil and no-op.
        completePendingWriter()
    }

    // MARK: - Blocking finish (for flush and save)

    private func finishCurrentSegmentBlocking() {
        guard let writer = currentWriter else { return }
        let url = currentSegmentURL

        currentVideoInput?.markAsFinished()
        currentAudioInput?.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        if writer.status == .completed, let url {
            lock.lock()
            segments.append(SegmentInfo(url: url, createdAt: Date()))
            lock.unlock()
        } else if let url {
            try? FileManager.default.removeItem(at: url)
        }

        currentWriter = nil
        currentVideoInput = nil
        currentAudioInput = nil
        currentSegmentURL = nil
        currentSegmentStartTime = .invalid
        hasStartedSession = false
    }

    // MARK: - Private

    private func startNewSegment(at time: CMTime) {
        let url = makeSegmentURL()
        currentSegmentURL = url

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            // Fragmented MP4 — file is valid at any fragment boundary
            writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)

            var videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000
                ]
            ]
            if let fmt = videoFormatDescription {
                let dimensions = CMVideoFormatDescriptionGetDimensions(fmt)
                videoSettings[AVVideoWidthKey] = Int(dimensions.width)
                videoSettings[AVVideoHeightKey] = Int(dimensions.height)
            } else {
                videoSettings[AVVideoWidthKey] = 1920
                videoSettings[AVVideoHeightKey] = 1080
            }

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            writer.add(videoInput)

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)

            writer.startWriting()

            currentWriter = writer
            currentVideoInput = videoInput
            currentAudioInput = audioInput
            hasStartedSession = false
        } catch {
            try? FileManager.default.removeItem(at: url)
            currentWriter = nil
            currentVideoInput = nil
            currentAudioInput = nil
            currentSegmentURL = nil
        }
    }

    private func deleteAllSegmentFiles() {
        lock.lock()
        for segment in segments {
            try? FileManager.default.removeItem(at: segment.url)
        }
        segments.removeAll()
        lock.unlock()

        // Also clean up any pending writer file
        if let url = pendingURL {
            pendingWriter?.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            pendingWriter = nil
            pendingURL = nil
        }
    }

    private func pruneOldSegments() {
        guard !isSaving else { return }
        lock.lock()
        let maxSegments = Int(ceil(bufferDuration / segmentDuration)) + 1
        while segments.count > maxSegments {
            let old = segments.removeFirst()
            try? FileManager.default.removeItem(at: old.url)
        }
        lock.unlock()
    }

    private func makeSegmentURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HighLitSegments", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent("seg_\(UUID().uuidString).mp4")
    }

    private func makeClipURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HighLitExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filename = "highlight_\(Int(Date().timeIntervalSince1970)).mp4"
        return tempDir.appendingPathComponent(filename)
    }
}

struct SegmentInfo {
    let url: URL
    let createdAt: Date
}

enum BufferError: LocalizedError {
    case emptyBuffer
    case compositionFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .emptyBuffer: return "No video data in buffer."
        case .compositionFailed: return "Failed to create video composition."
        case .exportFailed: return "Failed to export highlight."
        }
    }
}
