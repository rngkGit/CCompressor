# CCompressor

CCompressor is a native macOS utility designed for high-performance batch file compression and format conversion across images, audio, video, and PDF documents. Built exclusively with Swift and native Apple system frameworks, CCompressor delivers fast processing, privacy-preserving local execution, and a responsive macOS interface with zero external third-party dependencies.

---

## Features

- Multi-Format Compression: Process image, audio, video, and PDF files in unified batch operations.
- Format Conversion: Convert files individually or across entire batches using targeted output encoders.
- Intelligent Size Invariant: Output files are guaranteed never to exceed original file size during same-format compression. If compression does not yield savings, the original file is preserved and marked as optimal.
- Multi-Pass Image Optimization: Iterative encoding steps down compression quality if initial passes do not achieve storage reduction.
- Transparent Image Flattening: Automatic compositing onto white backgrounds when converting transparent formats (such as PNG) to JPEG.
- Hardware-Accelerated Video Transcoding: Multi-tier export preset fallback using AVFoundation with network streaming optimization.
- Streaming Audio Transcoding: Real-time AudioToolbox ExtAudioFile pipeline with custom bitrate allocation based on selected quality.
- Scaled PDF Raster Optimization: Vector and document downsampling with per-page JPEG compression.
- macOS Native Workflow: Drag-and-drop drop zones, Quick Look previewing, system context menus, and App Sandbox security-scoped folder management.
- Batch Analytics: Live visual storage comparison bar and metric breakdowns calculating total bytes processed, net savings, and average file footprints.

---

## Supported Formats and Capabilities

| Media Category | Supported Input Formats | Supported Output Formats | Underlying Apple Framework |
| :--- | :--- | :--- | :--- |
| Image | JPG, JPEG, PNG, HEIC, WEBP, TIFF, TIF, BMP, GIF, AVIF | JPG, PNG, HEIC, TIFF | ImageIO, CoreGraphics |
| Audio | MP3, WAV, M4A, AAC, FLAC, AIFF, AIF, CAF, ALAC, OGG | WAV, M4A (AAC), AIFF | AudioToolbox, AVFoundation |
| Video | MP4, MOV, M4V, AVI, MKV | MP4, MOV | AVFoundation |
| Document | PDF | PDF | PDFKit, CoreGraphics |

---

## Compression and Quality Architecture

CCompressor provides five quality presets alongside continuous slider adjustments from 5% to 100%:

| Preset | Quality Value | Description |
| :--- | :--- | :--- |
| Lossless | 100% | Preserves original data with zero lossy compression. Bypasses re-encoding unless format conversion is explicitly requested. |
| High | 80% | High fidelity preservation with moderate file size reduction. |
| Balanced | 65% | Default configuration. Balances visual and auditory fidelity against file size savings. |
| Smallest | 40% | Maximum compression intended for web delivery, rapid transmission, or email attachments. |
| Custom | 5% - 100% | Arbitrary quality factor configurable via the continuous slider. |

### Technical Compression Mechanics

- Images: Utilizes `CGImageSource` and `CGImageDestination` from ImageIO. Lossy quality is applied per frame. For format conversions requiring an opaque background (such as PNG to JPEG), alpha channels are evaluated and composited over a solid white RGB canvas.
- Audio: Uses AudioToolbox `ExtAudioFile` with signed 16-bit linear PCM intermediate streaming buffers. When encoding to M4A/AAC, `AudioConverterSetProperty` dynamically adjusts target bitrates between 64 kbps and 320 kbps in proportion to the quality slider and channel count.
- Video: Utilizes AVFoundation `AVAssetExportSession` with an adaptive preset hierarchy (HEVC 1080p, standard 1080p, 720p, 540p, 480p, and quality-based fallbacks). Outputs are configured with `shouldOptimizeForNetworkUse` for fast start playback.
- PDF: Loads documents via PDFKit and renders pages through CoreGraphics contexts. Each page is rasterized at a calculated resolution scale (72 DPI to 130 DPI based on quality) and encoded into compressed JPEG streams before assembly into a finalized PDF context.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| Command + O | Open file picker to import files or directories |
| Command + R | Start compressing all queued files |
| Command + K | Clear all items from the current queue |
| Control + Command + I | Toggle the Settings and Metrics inspector sidebar |
| Spacebar | Trigger Quick Look preview for the selected file |

---

## Installation

### Download from GitHub Releases

1. Navigate to the GitHub Releases section of the repository.
2. Download the disk image file: `CCompressor.v1.0.0.dmg`.
3. Open `CCompressor.v1.0.0.dmg`.
4. Drag `CCompressor.app` into your `Applications` folder.
5. Launch CCompressor from Applications or Spotlight.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later (only required if building from source)
- Apple Silicon or Intel 64-bit Mac

---

## Building from Source

1. Clone the repository and open the project in Xcode:
   ```bash
   open CCompressor.xcodeproj
   ```
2. Select the `CCompressor` scheme and `My Mac` as the run destination.
3. Build and run via `Product > Run` or press `Command + R`.

---

## Project Structure

The project is organized into clean domain layers separating models, services, view models, and views:

```
CCompressor/
|-- CCompressor/
|   |-- CCompressor.swift                   # Application entry point and window scene definition
|   |-- ContentView.swift                   # Root view hosting drop zone, file list, and toolbar
|   |-- Info.plist                          # Bundle properties and permissions configuration
|   |-- Models/
|   |   |-- CompressionItem.swift           # File item model, category enumeration, and metric helpers
|   |   `-- CompressionSettings.swift       # Presets, format preferences, and destination configurations
|   |-- Services/
|   |   |-- FileCompressorProtocol.swift    # Standard protocol for async compressor implementations
|   |   |-- FileCompressionDispatcher.swift # Central dispatcher handling paths, permissions, and invariants
|   |   |-- ImageCompressor.swift           # ImageIO-based image compression and conversion service
|   |   |-- AudioCompressor.swift           # AudioToolbox streaming transcode service
|   |   |-- VideoCompressor.swift           # AVFoundation video export service
|   |   |-- PDFCompressor.swift             # PDFKit raster optimization and re-compression service
|   |   `-- ThumbnailService.swift          # QuickLookThumbnailing asynchronous thumbnail cache
|   |-- ViewModels/
|   |   `-- CompressionManager.swift        # MainActor observable state manager and task coordinator
|   `-- Views/
|       |-- FileRowView.swift               # Individual file row with progress, format picker, and actions
|       |-- FileThumbnailView.swift         # Asynchronous image thumbnail component with category icons
|       |-- SettingsBarView.swift           # Inspector sidebar for quality, destination, and conversions
|       `-- StorageComparisonBarView.swift  # Graphical before-and-after storage distribution visualizer
`-- README.md
```

### Key Components

- CompressionManager: Orchestrates concurrent file processing via Swift structured concurrency (TaskGroup with a maximum concurrency limit of 2), handles drag-and-drop ingestion, folder security access scoping, and maintains batch statistics.
- FileCompressionDispatcher: Resolves output URLs, handles name collisions, creates output directories, verifies permissions, and enforces the non-expansion size invariant.
- ImageCompressor: Manages multi-frame image compression, alpha flattening, and format transitions.
- AudioCompressor: Manages low-level audio streaming buffers and bitrate configuration.
- VideoCompressor: Executes asynchronous export sessions with periodic progress polling.
- PDFCompressor: Manages CoreGraphics page contexts and embedded JPEG re-compression.

---

## License

Standard application project terms apply.
