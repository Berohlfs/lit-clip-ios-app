# LitClip

Capture sports highlights instantly. Tap once, save the last 30 seconds to your Camera Roll.

## How it works

1. Open the app — recording starts automatically
2. A rolling buffer keeps the last 30 seconds on disk at all times
3. Tap save — your highlight is exported to the Camera Roll in ~1 second
4. The buffer keeps rolling, ready for the next moment

## Features

- **One-tap save** — no start/stop, no trimming, just tap
- **30-second rolling buffer** — always recording, always ready
- **Fast export** — passthrough composition, no re-encoding (~1s)
- **Front/back camera toggle** — switch lenses mid-session
- **Apple Watch companion** — trigger saves from your wrist
- **Portrait lock** — UI stays portrait, orientation handled via metadata

## Under the hood

LitClip writes H.264-compressed `.mp4` segments to disk in a rolling window (~70MB max). When you save, segments are composed and trimmed via passthrough export — copying compressed packets directly instead of re-encoding 900 frames.

Key technical choices:
- **Disk segments over in-memory frames** — raw buffers at 1080p/30fps would use ~5.4GB RAM
- **Non-blocking segment rotation** — new writer starts before old one finishes, zero frame gap
- **Passthrough export** — ~200ms vs 4-8s with re-encoding
- **Flag-based pruning protection** — prevents segment deletion during export

## Tech stack

- Swift 6 / SwiftUI
- AVFoundation + Photos
- WatchConnectivity
- Zero third-party dependencies

## Project structure

```
HighLit/
├── HighLit/
│   ├── HighLitApp.swift              # Entry point
│   ├── Views/
│   │   ├── RecordingView.swift       # Main camera UI
│   │   └── CameraPreviewView.swift   # Preview layer
│   ├── ViewModels/
│   │   └── RecordingViewModel.swift  # State orchestration
│   ├── Services/
│   │   ├── CameraService.swift       # AVCaptureSession management
│   │   ├── VideoBufferManager.swift  # Rolling buffer logic
│   │   └── WatchConnectivityService.swift
│   └── Models/
│       └── VideoClip.swift
├── LitClipWatch Watch App/
│   ├── LitClipWatchApp.swift
│   └── ContentView.swift             # Watch save button
└── docs/
    └── ADRs/
        └── ADR-001-rolling-video-buffer.md
```

## Getting started

1. Clone the repo
2. Open `HighLit/HighLit.xcodeproj` in Xcode
3. Select a device or simulator and run

Requires camera access. Best tested on a physical device.

## License

MIT — see [LICENSE](LICENSE) for details.
