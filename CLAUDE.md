# CLAUDE.md

## Project
HighLit is an iOS app for capturing sports highlights instantly. Built with Swift 6 and SwiftUI.

## Core idea
The app continuously records video and keeps the last 30 seconds in a rolling buffer on disk. When the user taps save, the buffer is exported to the Camera Roll in ~1 second.

## Architecture

**Pattern:** MVVM (Services / ViewModels / Views / Models)

| Layer | Key files | Responsibility |
|---|---|---|
| Services | `VideoBufferManager.swift`, `CameraService.swift` | AVFoundation capture, rolling buffer, segment management |
| ViewModels | `RecordingViewModel.swift` | Orchestrates services, manages UI state |
| Views | `RecordingView.swift`, `CameraPreviewView.swift` | SwiftUI UI, camera preview |
| Models | `VideoClip.swift` | Data structures |

### Rolling buffer (VideoBufferManager)
- H.264-compressed 60-second `.mp4` segment files on disk (not raw frames in memory)
- Rolling window of segments, oldest pruned when count exceeds max
- Non-blocking segment rotation: new writer starts before old finishes (zero frame gap)
- `movieFragmentInterval = 1s` for resilience
- Flag-based pruning protection during export (`isSaving`)
- Passthrough export with `preferredTransform` metadata for orientation (no re-encoding)
- Max disk usage: ~70MB
- Full details in `docs/ADR-001-rolling-video-buffer.md`

### Concurrency model
- `VideoBufferManager` and `CameraService` are `nonisolated final class: @unchecked Sendable`
- Writer operations serialized on `writerQueue` (DispatchQueue)
- Shared state protected by `NSLock`
- UI updates dispatched to `@MainActor`

## Core flow
1. User opens the app → recording starts automatically
2. App writes H.264 segments to disk in a rolling window
3. Progress ring fills over 30 seconds
4. User taps save → segments composed, trimmed, exported via passthrough to Camera Roll
5. Buffer continues rolling during and after save

## Product principles
- One action to capture a highlight
- Zero friction during recording
- Fast and reliable saving (~1-1.5s)
- Minimal UI
- Works for any sport

## Constraints
- No AI detection
- No social features
- No accounts/auth
- No advanced editing
- Keep everything local and simple
- No memory leaks or orphaned files — every temp file has deletion coverage on all code paths
- UI locked to portrait; physical orientation detected via `UIDevice` for export metadata

## Key decisions and why
- **Disk segments, not in-memory frames** — raw CMSampleBuffer queue used ~5.4GB RAM and crashed instantly
- **60-second segments** — most 30s exports fall within a single segment (zero boundaries)
- **Non-blocking rotation** — blocking finishWriting dropped frames, causing visible flicker
- **Passthrough export** — re-encoding 900 frames took 4-8s; passthrough copies compressed packets in ~200ms
- **Flag-based pruning protection** — simpler and faster than copying segments to a staging directory
- **Orientation as metadata** — `preferredTransform` on the track avoids decode/re-encode entirely

## Focus
Prioritize the recording → buffer → save → Camera Roll loop above everything else.