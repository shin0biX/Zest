# Zest

A local-only, menu-bar file converter for macOS. Drag files in Finder, tap a modifier,
pick a target from the wheel — the converted file lands next to the original.

No windows, no uploads, no accounts. Everything runs on your Mac.

![Convert wheel](assets/convert.png)

## How it works

1. Drag any file (or selection, or folder) in Finder.
2. Tap a modifier **while still dragging**:
   - <kbd>⇧ Shift</kbd> — convert to another format
   - <kbd>⌘ Command</kbd> — run a tool (crop, compress, redact, snapshot…)
   - <kbd>⌃ Control</kbd> — quick actions (copy, move, AirDrop, Terminal…)
3. The wheel appears where you tapped; keep dragging onto a petal and release.

The central hub shows the file you're holding — icon, filename, format, and size. Drop
in a gap or the hub to cancel. Results are saved beside the originals, always.

Two wheel styles ship: the compact **petal fan** (shown above) and classic **concentric
rings**. Both float over the desktop with no panel behind them — switch in
Settings → General.

![Tools wheel](assets/tools.png)

## Formats

- **Images:** JPG · PNG · WebP · HEIC · TIFF · AVIF · BMP · GIF · PDF
- **Video:** MP4 · MOV · MKV · WebM · AVI · WMV · GIF
- **Audio:** MP3 · M4A · WAV · FLAC · OGG · Opus · AIFF · WMA
- **PDF →** DOCX · PPTX · XLSX · EPUB · TXT · Markdown · RTF · images
- **Documents:** DOCX · TXT · Markdown · HTML · EPUB · RTF
- **Spreadsheets:** XLSX · ODS · CSV · TSV
- **Subtitles:** SRT · VTT · TXT
- **Archives:** ZIP · TAR · GZIP (create and extract; RAR input via `unar`)

The wheel only offers conversions your Mac can actually perform — unavailable
combinations are hidden, not greyed out.

## Tools

Crop · resize · compress / exact size · add background · rotate · flip · adjust ·
grayscale · annotate · redact · strip tags · edit metadata · collage · read QR ·
snapshots (multi-frame) · trim · split · join · speed · GIF · mute · extract audio ·
normalize · bleep · redact video · redact audio · audio → video · channels · sample
rate · PDF merge / split / reorder / rotate / extract images · archive extract.

![Actions wheel](assets/actions.png)

**Actions:** AirDrop · Float (park files in a small always-on-top panel) · copy ·
move · copy path · open in Terminal · reveal in Finder.

## Settings

Five compact tabs live behind the status item:

- **General** — modifiers, wheel style (petal fan or concentric rings, both
  panel-free), feedback, collision policy (keep both / replace), Float behaviour,
  Terminal app.
- **Formats** — per-format defaults: image quality and size, audio bitrate and depth,
  video quality and max height, GIF frame rate and width, PDF and EPUB layout.
- **Compatibility** — a live input → output matrix generated from what your machine
  can really do.
- **Folders** — output behaviour and useful locations.
- **About** — version, engine status, onboarding.

Settings persist in `com.zest.app` and apply to every drag instantly.

## Requirements

- macOS 13 Ventura or newer, Apple Silicon or Intel
- Xcode command-line tools (`xcode-select --install`)
- Optional, for media formats: Homebrew `ffmpeg` (audio/video conversion and tools)
  and `cwebp` (WebP output). Zest detects them at launch and hides what's missing.

## Installation

Zest is a personal build distributed as source — there is no signed release binary.

```sh
git clone https://github.com/shin0biX/zest.git
cd zest/Zest
./build.sh          # release build, app icon, ad-hoc signature
open Zest.app       # launches in the menu bar — no Dock icon
```

`build.sh` compiles the release binary, applies the app icon, and ad-hoc signs the
bundle, so macOS runs it locally without a developer identity — no Gatekeeper dance,
because the app was built on your machine. Zest then lives in the menu bar and can be
enabled at login from Settings → General.

Prefer a quick debug build instead?

```sh
cd zest/Zest
swift build
.build/debug/Zest selftest   # 93 engine checks
.build/debug/Zest uitest     # 29 UI checks
```

## Command line

The same binary works headless — useful for scripting or CI:

```sh
Zest formats sample.png                      # what can this file become?
Zest convert sample.png --to pdf             # images → PDF accepts several files
Zest tool compress sample.png --params percent=50
Zest tool redactVideo clip.mp4 --params x=40 y=30 w=160 h=90 start=0 end=0.6 mode=box
Zest wheel /tmp/wheel.png --kind image --style fan --mode tools   # render the wheel
```

## Privacy

Zest never opens a network connection for its work. Conversion runs through local
system frameworks (ImageIO, PDFKit, CoreText, Vision) and, when installed, your
Homebrew `ffmpeg`. Files stay on your disk; nothing is uploaded, logged remotely, or
telemetered. Output always lands next to the source file, so you always know where
your data is.

## Development

Swift 5.9 · AppKit, programmatic UI · zero third-party packages.

```sh
cd Zest
swift build
.build/debug/Zest selftest        # engine suite (structural verification)
.build/debug/Zest uitest          # in-process UI suite, no permissions needed
./build.sh                        # release bundle
./Harness/run.sh all              # 12 end-to-end Finder-drag scenarios (needs Accessibility)
```

The [external harness](Zest/Harness/) drives real Finder drags through the shipped app
and verifies outputs structurally — every commit in this repo passed it. See
[AGENTS.md](AGENTS.md) for the full architecture, design decisions, and history.

## License

Personal, private build — no license granted for redistribution.
