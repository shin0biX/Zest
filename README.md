# Zest

### Your files, moving at the speed of a gesture.

Zest is a menu-bar file utility for macOS. Drag a file from Finder, tap a modifier,
and choose what to do from a floating wheel. Convert, edit, or organize files without
breaking your flow.

**Local by design** · **No account** · **No third-party packages**

![Zest’s default concentric-rings wheel](assets/rings.png)

## One drag. Three ways to work.

1. Start dragging a file, selection, or folder in Finder.
2. While still dragging, tap a modifier:
   - **⇧ Shift** — choose a conversion format
   - **⌘ Command** — choose a file tool
   - **⌃ Control** — choose an action
3. Drop on a choice. Zest runs it and shows progress; conversions are saved beside
   their source files.

The wheel appears where you tap and stays out of the way. Its center identifies the
file you’re holding. Drop on the center or outside the wheel to cancel. Choose whether
name conflicts keep both files or replace the existing one in Settings.

## A wheel that fits your workflow

**Concentric rings** are the default: formats, tools, and actions stay visible together.
The modifier highlights a ring, but every ring remains available while you drag.

Prefer a single focused surface? Switch to the **petal fan** in Settings → General. It
shows one surface at a time, with larger labels, and switches in place when you tap a
different modifier. Both styles float directly over the desktop.

![Petal fan with image tools](assets/tools.png)

## Convert across file types

![Conversion formats in the wheel](assets/convert.png)

Zest offers conversion targets according to the file you drop and the capabilities
available on your Mac.

| Input type | Conversion targets |
| --- | --- |
| Images | JPG · PNG · HEIC · WebP · AVIF · TIFF · BMP · GIF · PDF |
| Video | MP4 · MOV · MKV · WebM · AVI · WMV · GIF · MP3 · M4A · WAV |
| Audio | MP3 · M4A · WAV · FLAC · OGG · Opus · AIFF · WMA |
| PDF | DOCX · PPTX · XLSX · JPG · PNG · TXT · Markdown · EPUB |
| Documents | PDF · DOCX · TXT · Markdown · RTF · HTML · EPUB · Pages* |
| Presentations | PDF · JPG · PNG* |
| Spreadsheets | CSV · TSV · XLSX · ODS · PDF |
| Subtitles | SRT · VTT · TXT |
| Archives and folders | ZIP · TAR · GZIP |

Zest recognizes common image inputs including JPEG, HEIC/HEIF, WebP, AVIF, TIFF,
BMP, GIF, SVG, JPEG 2000, and camera RAW formats (DNG, CR2, NEF, ARW, RAF, ORF,
RW2); video inputs including MP4, MOV,
M4V, MKV, WebM, AVI, WMV, FLV, MPG/MPEG, TS/MTS, 3GP, and OGV; and audio inputs
including MP3, M4A, WAV, FLAC, OGG/OGA, Opus, AIFF, WMA, AAC, CAF, M4B, and APE.
Documents include DOC/DOCX, RTF/RTFD, HTML, Markdown, TXT, ODT, Pages, EPUB, and
WebArchive; presentations include PPT/PPTX, Keynote, and ODP; spreadsheets include
XLS/XLSX, ODS, CSV, TSV, and Numbers; subtitles include SRT, VTT, and SBV. PDF is
supported directly. Zest can create ZIP, TAR, and GZIP archives and extract ZIP, TAR,
GZIP, BZIP2, and XZ archives.

*Pages output requires Pages. Presentation conversion requires LibreOffice. RAR input
requires `unar` or `unrar`; 7z extraction requires `7z` or `7zz`. Some image and media
targets also depend on available encoders. Zest detects local capabilities and hides
unavailable choices.

## Tools for the file in front of you

- **Images:** crop, resize, compress, hit an exact file size, add a background, rotate,
  flip, adjust color, grayscale, annotate, redact, inspect or edit metadata, strip tags,
  make collages, and read QR codes.
- **Video:** compress, hit an exact size, trim, split, join, change speed, crop, rotate,
  capture one or more snapshots, make a GIF, mute, redact a region, extract audio,
  inspect metadata, and strip tags.
- **Audio:** compress, hit an exact size, trim, split, join, normalize, bleep or redact a
  time range, make a video from audio, change channels or sample rate, change speed,
  inspect metadata, and strip tags.
- **PDF:** compress, hit an exact size, merge, split, reorder or rotate pages, extract
  images, inspect metadata, strip tags, and read QR codes.
- **Documents and spreadsheets:** inspect or edit metadata and strip tags.
- **Subtitles and archives:** shift or merge subtitle timing; extract archives.

Batch workflows include turning several images into one PDF, joining media, making a
collage, and archiving a folder.

## Quick actions and shortcuts

![File actions in the wheel](assets/actions.png)

Send a file with AirDrop, park it in the Float panel, copy or move it, copy its path,
open its folder in Terminal, or reveal it in Finder. The status menu also keeps recent
operations for **Run again** or **Reveal**. Set favorite output formats in Settings and
use **⌘K** for Quick Convert without opening the wheel.

## Settings

Five compact tabs let you tune Zest without leaving the menu-bar workflow:

- **General:** drag modifiers, wheel style, feedback, keyboard control, collision
  handling, Float behavior, Terminal choice, and launch at login.
- **Formats:** per-format image quality and size, video quality and height, audio
  bitrate and bit depth, GIF frame rate and width, and PDF/EPUB layout defaults.
- **Compatibility:** a live input-to-output matrix for the tools available on this Mac.
- **Folders:** useful locations and output behavior.
- **About:** version, engine status, and the Getting Started walkthrough.

Quick Convert favorites are set by file type. Recent operations are stored locally so
you can run them again or reveal their output in Finder.

## Download

**[Download Zest 1.0 for macOS](https://github.com/shin0biX/Zest/releases/download/v1.0/Zest.dmg)**
· [View all releases](https://github.com/shin0biX/Zest/releases)

Open the disk image and drag `Zest.app` to Applications. This personal build is not
signed with an Apple Developer certificate, so macOS may require a one-time
right-click → **Open** → **Open**. Alternatively, remove the quarantine flag in
Terminal with:

```sh
xattr -cr /Applications/Zest.app
```

## Requirements

- macOS 13 Ventura or newer.
- Media conversion and media tools require `ffmpeg`; `ffprobe` adds media details.
  Install with `brew install ffmpeg`.
- WebP output uses `cwebp` or `ffmpeg`; AVIF output uses `ffmpeg` or a native macOS
  encoder.
- LibreOffice (`soffice`) enables presentation conversion. `unar`/`unrar` enables RAR
  extraction; `7z`/`7zz` enables 7z extraction.

These helpers are optional. Zest checks what is available and hides conversions or
tools it cannot run on the current Mac.

## Build from source

Install the Xcode Command Line Tools, then build the app:

```sh
xcode-select --install
git clone https://github.com/shin0biX/Zest.git
cd Zest/Zest
swift build                 # debug executable: .build/debug/Zest
./build.sh                  # release Zest.app bundle with icon and ad-hoc signature
open Zest.app
```

The project uses Swift 5.9, AppKit, and system frameworks. It has no third-party Swift
package dependencies. `build.sh` bundles working media helpers when available; if none
are bundled, Zest checks Homebrew and standard command paths at runtime.

## Command line

After `swift build`, run the same engines from the package directory:

```sh
.build/debug/Zest formats ./photo.png
.build/debug/Zest convert ./photo.png --to jpg
.build/debug/Zest convert ./one.png ./two.png --to pdf
.build/debug/Zest tool compress ./photo.png --params percent=50
.build/debug/Zest tool redactVideo ./clip.mp4 --params x=40 y=30 w=160 h=90 start=0 end=0.6 mode=box
.build/debug/Zest wheel /tmp/zest-wheel.png --kind image --style rings --mode tools
```

`formats` lists available targets for an input. `convert` accepts multiple images when
creating one PDF. `tool` takes a tool ID and optional `key=value` parameters. `wheel`
renders a preview PNG.

## Privacy

Zest processes files on your Mac using system frameworks and any optional local tools
you install. It does not upload files, use a cloud service, or send telemetry. AirDrop
is an explicit macOS sharing action when you choose it.

## License

Personal, private build. No license is granted for redistribution.
