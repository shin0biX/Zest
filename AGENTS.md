# AGENTS.md — Zest

Handoff context for any future session working in this repository.

Last verified: **2026-10-24** — compact graphite-glass fan, all suites and the external
harness green (see *Current state*). Read **Current state** and **Resume checklist**
before touching code. Historical sections at the bottom are labelled **History**; where they
disagree with the source code, **`Overlay.swift` and the other sources are
authoritative**.

## What this is

**Zest** — a local-only, menu-bar file converter for macOS. Drag files in Finder, tap a
modifier, and pick a target from the wheel. This is a personal build, not a distribution.

- Repository root: `/Users/shin0bix/Downloads/targe` (git root; the app is under `Zest/`).
- Remote: <https://github.com/shin0biX/zest>. HEAD is `9285117` (docs); the fan redesign
  sits **uncommitted** in the working tree (see *Current state*).
- Working backup made before the fan wheel work:
  `/Users/shin0bix/Downloads/targe_working_2026-10-23_1310` (670 MB, includes `.git`,
  sources, builds and uncommitted changes).
- The wheel, settings window, onboarding, and tool set were built for this app from
  layout cues and the operator's own mockups only. No third-party code or resources were
  copied. `RE/` holds local reference evidence (gitignored, not needed to build or run).
- No network, no uploads, no telemetry, no third-party Swift packages.

## Current state (authoritative)

- **Fan wheel: compact graphite glass, fully verified.** 384 pt petal flower
  (`fanInnerRadius 68`, `fanOuterRadius 192` — ~80% of the previous 480 pt disc, at the
  operator's request) around the dynamic file hub. Design details and prohibitions in
  *Approved fan-wheel design*; geometry constants live in `Overlay.swift`
  (`FanPetalGeometry`, `makeFanPetal`) and are authoritative.
- **Working tree (uncommitted, commit-ready):** `AGENTS.md`,
  `Zest/Sources/Zest/Overlay.swift`, `Zest/Sources/Zest/UITest.swift`,
  `Zest/Sources/Zest/CLI.swift`, `Zest/Sources/Zest/WelcomeWindow.swift`,
  `Zest/Harness/dragtest.swift`. Everything below was verified on this exact tree.
- **Verified 2026-10-24 on this tree:**
  - `swift build` — clean, zero warnings.
  - `selftest` — **93 passed · 0 failed · 0 skipped**.
  - `uitest` — **29 passed · 0 failed** (includes fan seam-separation and label-fit
    checks).
  - `./build.sh` — bundle rebuilt: `AppIcon.icns` present, `CFBundleIconFile` set,
    ad-hoc signed `com.zest.app`, launches and logs `options=616 tools=64
    ffmpeg=/opt/homebrew/bin/ffmpeg`. Ships **no** `Contents/Resources/Tools`; the app
    resolves Homebrew at runtime.
  - External harness — **12/12 scenarios in one batch** against this bundle
    (artifacts under `Zest/Harness/run/<scenario>/`). Log line reports
    `radius=130 outer=192`; the harness aims from it dynamically.
- **Host capabilities:** Accessibility is granted to the automation host (the harness
  runs from agent sessions and the operator's terminal); Screen Recording works, but
  output files, logs, and `Zest wheel` remain the primary checks.
- **Settings UI:** offscreen and live passes done — all five tabs and every format page
  build (`uitest`), the live window confirmed titlebar, traffic lights, orange pill
  tabs, corrected checkmarks, glass vibrancy, and the real About icon. Tab-by-tab
  persistence review remains manual.
- **Settings audit done, defects on record** — see *Open issues*; nothing fixed yet.
- **Media tools verified** through the shipping bundle binary; selftest asserts redaction
  pixels and both audio→video streams.
- **Stale debris:** `Zest/Zest 2.app` is an untracked older bundle containing binaries
  that trap on launch. Gitignored. Do not copy its Tools directory or ship that bundle.

## Approved fan-wheel design (current requirement)

The approved look is the operator's graphite design evolved into **smoked graphite
glass** (the operator asked for a glass finish over the graphite direction): charcoal
petals with subtle glass depth — dark neck pooling, a soft light pool on each rounded
cap, a whisper of shared sheen, and lit glass edges — thin neutral borders, a near-black
glass-puck hub, white/grey typography, and one restrained amber selected petal. All
three surfaces (convert / tools / actions) share one geometry and material system.

**Geometry** (summary — `Overlay.swift` is authoritative):

- `fanInnerRadius = 68`, `fanOuterRadius = 192` (compact 384 pt disc — ~80% of the
  earlier 480 pt; `discRadius = 192`, overlay clamp margin 206). Log line:
  `radius=130 outer=192` at scale 1.
- Petals fill **0.85 of the chord at every count**, so low-count fans grow wide paddles
  that fill the circle; `widthCap = 0.62 · (tip − innerTip)` only guards very sparse
  surfaces (three-petal folders) and never binds at eight or more.
- Shoulders `0.46 / 0.58` (nearly parallel sides, slight outward bow), `innerHalf =
  0.40 · outerHalf`, `capBulge = 0.58 · outerHalf`, neck starts at
  `fanInner − 4 · scale` (petals emerge from behind the hub). Label anchor
  `sideInner + 0.73 · length` (in the petal's wide zone), label width
  `2 · halfWidth(t) − 3 · scale` — the compact wheel needs most of the petal width for
  labels; `fanLabelFont` ladders down to 8 pt as a floor.
- No per-petal offsets, no wrap-boundary special case; one path serves drawing, label
  fitting, selection, and hit-testing.

**Palette** (hex-derived literals in code):

| Use | Value |
| --- | --- |
| Petal fill gradient | `#202124` (neck) → `#2A2B2F` (body) → `#303136` (cap), stops at 0 / 0.45 / 1 |
| Petal border | `#4A4B52` (1 pt) plus a 0.75 pt white 14 %-opacity glass edge light |
| Glass cues | neck pooling (black 24 %), cap light pool (white 13 %), shared sheen (white 6 %) |
| Hub fill / border | `#191A1D` (top-light gradient `#1E1F23` → `#151619`) / `#3B3C40` (1.5 pt) with a lit inner rim (white 13 %) and soft top light |
| Primary / secondary text | `#F0F0F2` / `#A1A1A7` |
| Normal icons | `#D0D0D5` (petals); hub icon `#F0F0F2` |
| Selected fill / highlight | `#78451F` → `#965B2A` with a warm cap pool (amber-white 24 %) |
| Selected border / icon | `#C98535` (1.4 pt) with a warm glass edge / `#FFB34D` |
| Selected label | `#FFFFFF` |

**Material rules:** one restrained fill gradient per petal plus three glass cues —
dark pooling at the neck, a soft light pool on the cap, a whisper of sheen — then the
fine border with its lit inner edge, and a small neutral shadow per petal (the selected
petal's shadow is faintly warm). Everything is neutral grey except the amber selection;
the glass cues stay at 6–24 % opacity so the wheel keeps its matte character. Petal
icons are 20 pt (22 selected), stacked above labels in screen space; hub content is
sized for the 68 pt hub (26 pt icon, 14 pt semibold filename, 10 pt metadata). Labels
are sentence case, semibold, measured against `petal.labelWidth`. The hub shows the real
icon, filename, and `FORMAT · size` metadata. **Neither wheel mode paints a backdrop
plate** (the ring layout's plate was removed at the operator's request — rings float
over the desktop like the fan); shadows stay local to petals and hub.

**Explicitly prohibited in the fan** (all were rejected by the operator):

- No blue, violet, lavender, pink, cyan, or teal accents.
- No neon lighting, luminous rims, bright white outlines, or glowing halos.
- No excessive bloom, radial hotspots, chrome, or inflated plastic surfaces.
- No square or rounded-square backdrop, card, or plate behind **either wheel mode**
  (the rings layout included one until 2026-10-24, when the operator asked for just
  the rings).

**Where the colors live:** `drawFanPetalBody`, `drawFanPetalShadow`, `drawFanHub`, and
`drawFanContent` in `Overlay.swift` — edit those four places only.

**Seam guarantee:** the geometry keeps a visible channel between every adjacent pair
(including Grayscale/Adjust and the wrap boundary). `uitest` asserts path containment at
the seam plus a ≥ 4.5 pt model gap at every sampled radius, and fan label fit.

## Architecture

### Source tree (24 app Swift files + harness)

```
targe/
  AGENTS.md
  RE/                          # local reference material, gitignored (not shipped)
  Zest/
    Package.swift
    build.sh
    Resources/
      Info.plist          AppIcon.icns       make-icon.swift
    Sources/Zest/
      main.swift          App.swift           Support.swift       Prefs.swift
      Catalog.swift       DragWatcher.swift   Overlay.swift       HUD.swift
      Planner.swift       KeyTap.swift        ImageEngine.swift   PDFEngine.swift
      MediaEngine.swift   TextTools.swift     OfficeWriters.swift DocEngine.swift
      SubtitleArchive.swift                   Tools.swift         ToolUI.swift
      Floating.swift      CLI.swift           UITest.swift
      Settings.swift      WelcomeWindow.swift
    Harness/
      dragtest.swift      run.sh
    Zest.app              # release build output (current)
```

| File | Role |
| --- | --- |
| `main.swift` | CLI dispatch for real arguments; otherwise `NSApplication` + `AppDelegate`. Ignores Finder `-psn_…` arguments. |
| `App.swift` | App delegate, status item, Services provider, menu, Settings/Welcome entry points, engine status. |
| `Settings.swift` | Compact 480×620 five-tab settings window: orange pill tabs, flat card rows, search/sidebar Formats, compatibility matrix, Folders, About, `exerciseForTesting` seam. |
| `WelcomeWindow.swift` | Five-page onboarding, keycaps, half-scale fan preview (capped at eight petals). |
| `Support.swift` | `Shell`, `ToolFinder` (execution-validated candidates), `AppIcon`, `Kind`, `KindDetector`, `Naming`, `Bytes`, `Temp`, `Log`, `MediaProbe`, `onMain`/`onMainSync`, `ZestError`. |
| `Prefs.swift` | Suite `com.zest.app` (falls back to `.standard` when the bundle id is `com.zest.app`); trigger keys, wheel/style/float/terminal choices, per-format defaults (`qualityPreset`, `preserveMetadata`, `imageCompression`, `imageSize`, `videoQuality`, `videoHeight`, `audioBitrate`, `audioBitDepth`, `gifFPS`, `gifWidth`, `pdfLayout`, `epubLayout`), `conversionParams(for:)`. |
| `Catalog.swift` | Format tables, tool/action tables, per-kind wheel choices, option counts. Includes `archiveTools` and Add BG / Snapshots. |
| `DragWatcher.swift` | Permission-free drag detection: `pressedMouseButtons`, modifier transitions, `NSPasteboard(name: .drag)`. |
| `Overlay.swift` | Non-activating `OverlayPanel`, `WheelView` (fan + rings), `FanPetalGeometry` petal paths and label metrics, path hit-testing, graphite fan rendering, dynamic hub, demo/preview modes, drag destination. |
| `HUD.swift` | Exactly one floating progress panel; `HUDController.shared`; reveal-on-click. |
| `Planner.swift` | Committed choice → conversion/tool/action; passes per-format params and source-keyed PDF/EPUB layout; batch image→PDF; Terminal choice; HUD. |
| `KeyTap.swift` | Optional CGEventTap for keyboard navigation (Accessibility). |
| `ImageEngine.swift` | ImageIO encode/decode; crop/resize/rotate/flip/adjust/grayscale/markup; `addBackground`; SVG; WebP via `cwebp`; metadata copy. |
| `PDFEngine.swift` | Page rendering; images→PDF; PDF→DOCX/PPTX/XLSX/EPUB/TXT/MD/RTF; fixed-layout EPUB; merge/split/reorder/rotate/compress/extract/QR/metadata. |
| `MediaEngine.swift` | ffmpeg/ffprobe conversions, media tools (including video/audio redaction and audio→video), param-driven CRF/bitrate/height/GIF; **defines `Convert` dispatcher at the bottom**. |
| `TextTools.swift` | CoreText paginated PDF, RTF, HTML/Markdown, `DocxReader`/`DocxWriter`, `EpubWriter`, `ZipUtil`. |
| `OfficeWriters.swift` | Minimal `PptxWriter`, `XlsxWriter`, `OdsWriter`, `SheetReader` (XLSX/ODS/CSV/TSV). |
| `DocEngine.swift` | Documents/EPUB/Pages/slides; consumes `pdfLayout`/`epubLayout`; `SheetEngine`, table-to-PDF. |
| `SubtitleArchive.swift` | SRT/VTT parse/write/shift/merge; zip/tar/gzip create/extract/convert; `ArchiveEngine`. |
| `Tools.swift` | `ToolRunner` for every tool id; image compression, metadata, collage, QR, frame, snapshots, archive extract, video/audio redaction, audio→video. |
| `ToolUI.swift` | Generic NSAlert forms, crop/markup/rect editors, video frame picker, metadata editor, QR panel, Add BG / Snapshots / Redact Video / Redact Audio / Audio to Video forms. |
| `Floating.swift` | Float action panel: retained non-activating panel, thumbnails, per-row close, drag-out, add-to-existing. |
| `CLI.swift` | Headless `formats`, `convert`, `tool`, `selftest`, `uitest`, `wheel`; owns the 93-check engine suite. |
| `UITest.swift` | `Zest uitest`: 29-check in-process UI smoke suite; fake drag context; fan and settings coverage. |
| `Harness/dragtest.swift` | Standalone external harness. Finder AX + CGEvent drags through the real bundle, verifies outputs structurally. |
| `Harness/run.sh` | Builds `dragtest` into `.build/harness/` and runs it (`all` or one scenario, `--keep-running`). |

### Routing notes

- Drag flow: `DragWatcher` → `OverlayController.show` → `WheelView` (drag destination) →
  `Planner.submit`. The wheel anchors where the trigger was pressed and does not follow
  the mouse.
- **Style choice:** `OverlayController` assigns `Prefs.wheelStyle` before surfaces and
  emphasis. `WheelView` itself defaults to `.rings` for tests. Do not flip that default
  without updating the geometry tests.
- **Rings:** `Catalog.surfaces(for:)` returns every non-empty surface in
  formats → tools → actions order; rings are concentric, outer first. `emphasis` only
  brightens the ring named by the trigger modifier; it never removes a ring. A commit
  carries the ring's mode, not the armed one.
- **Fan:** one surface at a time, rebuilt by `emphasize(_:)`. `Catalog.surfaces` still
  supplies all surfaces; the fan picks the emphasized one. `rings` contains exactly one
  ring at `fanInnerRadius … fanOuterRadius`. Switching modes keeps the wheel anchored.
- **Petal path:** `FanPetalGeometry` owns the path, cap sub-path, label metrics and
  hit-test. The path is two shoulder cubics plus elliptical inner/outer caps in
  petal-local coordinates, rotated by `angle`. `FanPetalGeometry.halfWidth(at:inner:outer:)`
  evaluates the same cubic; label fitting and drawing must keep using it. Steeper
  shoulder controls saturate the width by mid-length and pinch the neighbour gaps (see
  *History* — the original Grayscale/Adjust overlap). Do not reintroduce per-petal
  angular offsets or a second petal path. `wedgePath` for rings still needs its outer
  arc counter-clockwise and inner arc clockwise; inverting either fills the annulus.
- Ring hit-testing picks the ring by radius, then the slice by angle. Fan hit-testing is
  `petal.path.contains(point)` over `fanPetals` after a `r ≥ fanInner` guard (petal
  necks tuck under the hub rim, so the radius guard keeps the hub a cancel); a point in
  the gap is also a cancel. Do not go back to an angular sector test for the fan.
- **Drag handlers live on `WheelView`, not `OverlayPanel`.** `NSWindow`/`NSPanel` does not
  expose overridable `NSDraggingDestination` methods, and a plain view receives the events
  reliably. Do not move them back to the panel.
- `OverlayPanel.cancelOperation` calls an `onCancel` closure so controller state is
  cleared; it must not close the window directly.
- No `NSApp.activate` on the drag path. The overlay is `.nonactivatingPanel`; activating
  cancels the Finder drag. Demo/Settings/Welcome paths may activate.
- `HUDController.shared` owns one panel. `FloatingFiles` retains one panel per Float
  invocation and tracks `lastURLs` for add-to-existing and per-row close.
- Batch routing: images→single PDF in `Planner`; folder/multiple archives in `Planner`;
  batch tool ids (`join`, `merge`, `collage`) in `Planner` + `ToolRunner.isBatch`.
- `Convert.perform(_:to:params:)` is at the bottom of `MediaEngine.swift`; there is no
  `Convert.swift`.
- CLI uses the same engines as the app. It initializes `NSApplication.shared` first but
  never enters the run loop.
- `DragWatcher.process(flags:pressed:change:)` is the testable seam: the timer samples
  `NSPressedMouseButtons`, modifier flags, and the drag pasteboard change count, then
  calls it. `uitest` drives the seam directly; do not test by sleeping on the timer.
- Overlay logging is load-bearing for the external harness: `Wheel mode=… count=… anchor=x,y
  screen=WxH radius=… outer=… rings=… choices=id,id,…` on every arm and mode switch, and
  `Choice <id> mode=…` on commit (`Choice cancel` on cancel). In fan mode `rings` has one
  entry, `radius` is the ring midpoint (`130` at scale 1) and `outer` is `192`. Keep the
  format stable or update the harness.
- `Zest wheel <out.png> [--kind …] [--style fan|rings] [--mode …] [--hover N]` renders
  the wheel offscreen at 2×. It is the deterministic visual check. Screen Recording is
  available on this host, but do not rely on screenshots for assertions.
- `DragWatcher.scheduleDisarm` keeps the wheel alive for 0.22 s after mouse-up.
  `OverlayController.handleDisarm` then closes immediately if the pointer is outside the
  wheel, or waits up to 1 s for `performDragOperation` if the pointer is on it.
- Settings observers: `.zestSettingsChanged` rebuilds the status menu; `.zestOpenSettings`
  opens Settings from Welcome. `setTrigger` rejects duplicate modifiers and rebuilds the
  General tab.
- `SettingsWindow.exerciseForTesting()` must keep building all tabs and all format pages;
  it caught the Auto Layout crashes that only appear after the document views are attached.

## Build and run

```sh
cd Zest
swift build                       # debug, for quick engine work
./build.sh                        # release bundle, icon, ad-hoc signature
open Zest.app
```

- Bundle id: `com.zest.app`; settings live in that UserDefaults suite.
- Logs: `~/Library/Logs/Zest.log`.
- Ad-hoc signing is sufficient; no developer identity.
- Debug binary: `.build/debug/Zest`. Release binary: `.build/release/Zest`.
- `build.sh` copies `Resources/AppIcon.icns` and optionally bundles media tools
  (ffmpeg, cwebp). It tests every candidate with its version flag first; a copy that
  exists but traps is never shipped. `ZEST_TOOLS_SRC` picks a Tools directory explicitly,
  otherwise the first `/Applications/*.app/Contents/Resources/Tools` that passes, then
  `Resources/Tools/`. On this host no candidate passes, so the bundle has **no** Tools
  directory and `ToolFinder` resolves Homebrew.
- `ToolFinder` validates every candidate at runtime (2 s version probe, cached). A broken
  bundled binary is treated as missing instead of shadowing a working Homebrew copy.
- Launch-at-login uses `SMAppService.mainApp`. An ad-hoc signed bundle may report
  `.requiresApproval` or throw; Settings reverts the checkbox and alerts.

### Verification snapshot

```sh
cd Zest
swift build                       # clean (debug)
.build/debug/Zest selftest        # 93/0/0
.build/debug/Zest uitest          # 29/0 (seam + label fit included)
.build/debug/Zest wheel /tmp/wheel-fan.png --kind image --style fan --mode tools
.build/debug/Zest wheel /tmp/wheel-fan.png --kind image --style fan --mode convert --hover 3
.build/debug/Zest settings-preview 0 /tmp/settings-general.png   # tabs 0…4
./build.sh                        # release + Zest.app + icon + ad-hoc sign
./Harness/run.sh all              # external Finder drags, 12 scenarios
./Harness/run.sh basic            # one scenario (useful after a flake)
open Zest.app                     # launch + log
```

Do not mark an interaction row as fully tested without the real drag or the manual run.

### Headless usage

```sh
.build/release/Zest formats sample.png
.build/release/Zest convert sample.png --to pdf
.build/release/Zest tool compress sample.png --params percent=50
.build/release/Zest tool metadata sample.jpg --params remove=1
.build/release/Zest tool qr sample.png
.build/release/Zest tool redactVideo clip.mp4 --params x=40 y=30 w=160 h=90 start=0 end=0.6 mode=box
.build/release/Zest tool redactAudio track.wav --params start=0.1 end=0.4 mode=tone frequency=880
.build/release/Zest tool audioToVideo track.wav --params width=1920 height=1080 color='#1C1C1E'
.build/release/Zest selftest
.build/release/Zest uitest
.build/release/Zest wheel /tmp/wheel.png --kind image --style fan --mode tools
```

`convert` accepts multiple files for images→PDF. `tool` accepts repeated `key=value`
pairs after `--params`; JSON values must be shell-quoted. `selftest` and `uitest` exit
non-zero on any failure. `uitest` runs in-process: it creates windows, drives the wheel
and planner, and closes them; it does not need Accessibility, Screen Recording, or a
Finder session. `wheel` renders the current wheel for a kind to PNG at backing scale;
use it to inspect fan petals, ring geometry and label fit.

## Selftest coverage

Samples synthesized in a temp root: PNG ×2, MP4 ×2, WAV, TXT, PDF ×2, DOCX, XLSX, CSV,
SRT ×2, ZIP. The suite runs **93 checks**:

- Images: PNG→JPG/WebP/HEIC/AVIF/TIFF/BMP/GIF/PDF, two images→one PDF, resize, crop,
  rotate, flip, adjust, grayscale, compress, annotate, **add background**, strip
  metadata, collage.
- PDF: →JPG/PNG/TXT/MD/DOCX/PPTX/XLSX/EPUB/RTF; merge, split, reorder, rotate, extract
  images, extract an embedded image at native size, mixed-page-size compression,
  compress, strip metadata; scanned PDF→TXT through Vision OCR; **fixed-layout EPUB**
  (page images plus `pre-paginated`).
- Documents: TXT→PDF/DOCX/RTF/HTML/EPUB, DOCX→PDF/TXT, Markdown→HTML/PDF, DOCX
  metadata strip; **flowing PDF layout**.
- Sheets: CSV→XLSX/ODS/PDF, XLSX→CSV/ODS/PDF, ODS→CSV.
- Subtitles: SRT→VTT/TXT, shift, merge.
- Archives: extract, **extract tool**, ZIP→TAR, folder→ZIP, TXT→GZIP,
  folder→GZIP→extract.
- Media (when ffmpeg is available): MP4→MOV/MP3/GIF, WAV→FLAC, trim, split, join,
  speed, snapshot, **multi-frame snapshots**, GIF, mute, extract audio, normalize,
  bleep, **redact video**, **redact audio**, **audio→video**, channels, sample rate,
  compress, metadata strip.

Outputs are verified structurally, not just by size: `PDFDocument` must open with pages;
OOXML must have `[Content_Types].xml` at the archive root; EPUB/ODS must have
`mimetype` at the root; archives must not contain `__MACOSX`; images must reload through
ImageIO; media must pass `ffprobe` when it is available. Add BG asserts a larger square
canvas. Archive extract asserts a non-empty directory. Snapshots asserts both files.
Video redaction samples the output at two times and asserts the box pixel is black
inside the range while the same pixel stays white outside it. Audio→video asserts both
video and audio streams through ffprobe. The compression check compares page boxes
before and after. The embedded-image check asserts the extracted pixel size matches the
XObject, not the page render.

If you add an engine or converter, add a selftest check in the same session. The count is
expected to grow; do not weaken structural verification to keep the count stable.

## UI smoke suite (`Zest uitest`)

`UITest.swift` runs **29 checks** in-process and needs no TCC permissions. The two fan
checks added with the petal redesign: **fan seam separation** — for every adjacent petal
pair, wrap boundary included, the seam point is inside neither path at radii sampled
through the whole body, and the shared width profile leaves a ≥ 4.5 pt gap; and **fan
label fit** — every title on every surface fits its petal's `labelWidth` at the font the
surface selects.

- Catalog: every kind × mode has choices; the source format is not offered; tool ids are
  unique; no choice appears on two surfaces of the same wheel.
- Wheel: every slice in every ring hit-tests to its choice; **fan mode renders one ring,
  switches convert → tools → actions, and every fan slice hit-tests**; hub/outside cancel
  (the fan also cancels at `r < fanInner`, since petal necks tuck under the hub); every
  ring label fits its chord at `WheelView.labelFont(for:in:)`; hover follows rings and
  clears in the hub; a fake drop commits the tools ring and reports `.tools`; fan seams
  stay separated and fan labels fit (`fanLabelFont` / `fanFormatFont` against
  `petal.labelWidth`).
- Overlay: opens at the anchor, switching emphasis keeps all three rings (the test forces
  `wheelStyle = .rings` for this case), Escape closes, arrows step across rings and Return
  commits with the hovered ring's mode.
- DragWatcher: Shift arms after the drag pasteboard changes and release disarms after the
  grace period; a new drag cancels a pending disarm; Command then Control then Shift
  switches modes in order.
- Planner: image→JPG beside the source, two images→one 2-page PDF, folder→ZIP.
- Naming: `keepBoth` produces `photo 2.png`; `replace` reuses `photo.png`.
- HUD: one panel, success and failure text, dismiss closes it.
- Float: panel appears with both rows.
- Settings: general window builds and reflects collision prefs; **every tab and every
  format page builds**.
- Services: `convertWithZest` opens the wheel with one image and the right kind.
- Status item: icon, Preview Wheel, Settings…, Quit are present.
- Actions: Copy Path writes the clipboard.

Limits: no synthetic mouse events, no Finder drag session, no AirDrop, no modal tool
editors, no Float drag-out/double-click, no menu tracking, no Welcome page clicks. The
external harness covers Finder drags, the crop/annotate/redact/metadata editors, PDF
Split, keepBoth/replace, and Float row close; AirDrop, Float drag-out/double-click,
Welcome, the live Settings window, and menu tracking remain manual. The three media
forms are modal and are not in `uitest`; selftest plus a shipping-bundle run cover their
engine paths, but the forms still need a visual check.

## External drag harness

Synthetic events work because the automation host is trusted (Accessibility granted).
The harness is a standalone binary (`Zest/Harness/dragtest.swift`) built by
`Harness/run.sh`; it never links Zest's code and lives outside the shipping sources. It
runs twelve scenarios:

| Scenario | Path exercised |
| --- | --- |
| `basic` | PNG → JPG through the Shift surface |
| `tools` | PNG → Grayscale through the Command surface |
| `actions` | PNG → Copy Path through the Control surface |
| `folder` | folder → ZIP through the Shift surface |
| `twopdf` | two selected PNGs → one two-page PDF |
| `pdfsplit` | three-page PDF → Split form → Apply → three one-page PDFs |
| `crop` | Crop editor → drag 30–70% → Crop → ~512×320 PNG |
| `markup` | Annotate editor → drag a box → Save → red stroke in the pixels |
| `redact` | Redact editor → drag a box → Redact → black fill in the pixels |
| `metadata` | Metadata editor → Title/Author fields → Save → TIFF/PNG tags |
| `collisions` | keepBoth makes `dup 2.jpg`; replace rewrites `dup.jpg` |
| `float` | two files → Float panel → row close → header close |

Mechanics:

- Find the Finder icon: activate Finder, read the browser window by title (AXDocument is
  often nil), ensure icon view through the `AXRadioButton` described `icon view`, then the
  `AXImage` whose `AXFilename` matches. Click with `AXPosition` + half of `AXSize`.
- For a multi-file selection, click the first icon, then send Cmd+A. Scenario folders
  contain only the inputs, so select-all is exact.
- Post mouse-down, then press the trigger, then drag. **A synthetic `.flagsChanged` sent
  mid-drag is not reliably re-targeted by the window server**; press the modifier between
  mouse-down and the first drag step. `uitest` drives mid-drag mode switching in-process.
- Parse the newest `Wheel mode=… anchor=x,y screen=WxH radius=… outer=… rings=… choices=id,id,…`
  line. In **fan** mode there is one ring and `radius` is the fan mid radius (`130` at
  scale 1; `outer` is `192`). In **rings** mode `mode` names the emphasized ring and
  `radius` is its mid radius. Slice 0 is centered at the top:
  `step = 2π/count`, `start = π/2 + step/2`,
  `angle = start - (index+0.5)·step`. Convert the AppKit wheel point to CG top-left
  coordinates.
- **Pause 0.35 s after the arm line before moving to the slice.** The overlay is ordered
  front and fades in just after logging; a synthetic drag that moves immediately can
  reach the slice before AppKit sends `draggingEntered`, which looks like "the drop never
  reached the wheel". Re-post the trigger flag down if `NSEvent.modifierFlags` lost it.
- Drag to the slice, mouse-up, release the modifier, and wait for the latest `Choice <id>`
  line.
- Tool windows: the AX frame minus the known content height gives the title bar; the
  canvas is the top `582` pt (crop) or `668` pt (markup) of the content. Replicate the
  centered image rect, drag between normalized points, then press the window's button by
  AX title.
- Metadata: find the alert by static text, set the first two `AXTextField`s (Title,
  Author), press **Save**.
- Collisions: `defaults write com.zest.app collision keepBoth|replace` and wait ~0.6 s;
  a running Zest picks the value up through cfprefsd. Always restore `keepBoth`.
- Float: find the borderless panel by its static text, then click the close buttons by
  geometry. The title does not change when rows close; assert on row names.
- Finder occasionally ignores a synthetic press. The harness re-selects the icon and
  retries the drag up to three times; crop also retries once if the Crop button stays
  disabled. If the wheel arms but no `Choice` line arrives, it logs `drop retry n/3`,
  cancels the drag, waits 1.3 s for the disarm timeout, and starts a fresh drag.
- A synthetic drag can end just after the overlay arms, especially on the first scenario
  after launch, and a freshly posted synthetic modifier can fail the harness's own
  visibility check ("synthetic shift is not visible to the system"). Both are
  test-side flakes: rerun the failed scenario once before investigating app code. Inspect
  `Drag start`, `Drop enter`, `Drop perform`, and `Wheel disarm` before changing anything.
- Verify structurally (ImageIO reload, page count, archive listing, tag values,
  red-pixel count, black-pixel count). Artifacts land in `Zest/Harness/run/<scenario>/`.
- If the harness reports "Accessibility is not granted", the fix is to enable the
  **terminal or host app that launches it** in System Settings → Privacy & Security →
  Accessibility and relaunch it — never `dragtest` itself (its ad-hoc signature changes
  on every rebuild), and never `sudo` (a root-owned `.build/harness/dragtest` blocks the
  next rebuild).

## Open issues

### Settings audit (executed 2026-10-24; nothing fixed yet)

Every Formats control was traced from its `Settings.swift` setter through
`Prefs.conversionParams(for:)` into the engine, and the drivable ones were executed.

**Proven by execution:**

| Setting | Evidence |
| --- | --- |
| Image quality (jpg/webp/heic/avif) | same 1600×900 JPEG: 0.95 → **438,116 B**, 0.45 → **147,512 B** |
| Image size, longest edge (jpg/png) | `maxDimension=720` on 1600×900 → **720×405** |
| GIF frame rate + max width | 5 fps/320 → **320×180, 5/1**; 20 fps/960 → **960×540, 20/1** |

**Wired correctly, verified in code** (the CLI cannot reach them: `Zest convert` calls
`Convert.perform` with empty params, so format defaults only apply on the drag path):

- Video quality → `-crf` for libx264/libvpx; video max height → `scale=-2:min(ih,H)`,
  downscale-only
- Audio bitrate → `-b:a`; audio bit depth → `pcm_s16le`/`s24le`/`s32le`
- PDF layout, read from the **source** extension so the DOCX/Pages page drives DOCX→PDF
- EPUB layout with the PDF→EPUB fallback to the EPUB page's key

**Broken or misleading:**

1. **Compression Balanced/Strong does nothing.** The control writes
   `Prefs.imageCompression`, `conversionParams` copies it to `params["imageCompression"]`,
   and no engine reads that key. Wire it or delete the control.
2. **Preserve metadata is a silent no-op here.** It defaults to on, but
   `ImageEngine.convert` carries tags only through `ToolFinder.exiftool`, and exiftool is
   not installed on this host. Verified: a JPEG with `UserComment=ZestMetaProbe`
   converted to PNG comes back with `UserComment=nil`, no error. The **Metadata tool** is
   unaffected — it writes tags natively through ImageIO — so the fix is to reuse that
   path instead of depending on an external binary.
3. **Dead controls on specific formats:** video quality on AVI and WMV (hardcoded
   `-q:v 4`), audio bitrate on OGG (hardcoded `-q:a 5`), audio bit depth 32-bit on AIFF
   (silently becomes 24-bit).
4. **EPUB→PDF has no PDF-layout row** (only DOCX/Pages do), so EPUB sources always take
   the global default.
5. **`Zest convert` ignores every format default** — empty params, so headless output
   never matches a drag.

General settings all reach something: launch at login, sound/haptics (one toggle gates
both), Float behaviour, Terminal choice, collision policy, keyboard control, wheel style.
**Appearance is the only partial** — Glass/Solid restyles the Settings window, not the
overlay.

### Remaining gaps and known limits

1. **The mid-drag modifier tap is not machine-verified.** The external harness presses the
   trigger between mouse-down and the first drag step because macOS does not reliably
   re-target a synthetic drag to a panel that appears mid-session. Fan and ring drops are
   driven by real Finder drags, and `uitest` covers the mode switch logic; one manual
   drag with a real Shift/Command/Control tap is still required.
2. **The fan wheel has no pagination.** It draws every choice, up to 15 image tools, as
   a petal. The petal geometry is verified (`uitest` seam and label checks); low-count
   fans fill 0.85 of their chord, so their petals are wider and the channels stay even.
   Showing a smaller set at a time is not implemented.
3. **PDF compression still rasterizes.** Text, links, annotations, and form fields are
   lost. Per-page media boxes are preserved; compression remains image-based.
4. **Embedded image extraction has a fallback.** Only image XObjects are pulled at native
   size. Inline images, stencil masks, and pages with no image XObject render the whole
   page at the requested DPI.
5. **OCR is a fallback, not document reconstruction.** `VisionOCR` runs only when PDFKit
   returns no text. Layout, tables, columns, and images are not rebuilt.
6. **DOCX reading is plain text.** `DocxReader` extracts `<w:t>` runs; DOCX→PDF/TXT/MD
   drops styling, tables, and images. Native `DocxWriter` output is minimal.
7. **Document layouts are applied, with limits.** `pdfLayout` selects flowing text versus
   editable rich paragraphs; "editable" still means a CoreText-rendered PDF, not a
   tagged or reflowable document. `epubLayout=fixed` produces page images with
   `pre-paginated` metadata, so the text is not selectable or reflowable. Image
   "compression" (Balanced/Strong) is a **dead control** — see the settings audit.
8. **Metadata preservation depends on ExifTool, which is not installed here.** Tags are
   copied after re-encode only when `ToolFinder.exiftool` resolves; otherwise the copy is
   skipped silently and the conversion drops EXIF/GPS/IPTC. Verified with a `UserComment`
   tag: present on the source, absent on the output. Orientation and pixel-dimension tags
   are not sanitised either. The Metadata tool itself is fine — it writes tags natively
   through ImageIO.
9. **SVG fallback quality depends on the host.** `rsvg-convert` is preferred; this Mac
   uses `qlmanage -t`.
10. **No media tools are bundled on this host.** `ffmpeg`, `ffprobe`, and `cwebp` resolve
    from Homebrew/PATH. `build.sh` only bundles a candidate that passes its version probe;
    binaries that trap with 133 must not be bundled.
11. **Pages/Keynote/Numbers and LibreOffice outputs remain unavailable.** Pages output
    requires `/Applications/Pages.app`; slide/legacy Office output requires `soffice`.
    Options are gated.
12. **AirDrop, Float drag-out/double-click, Services menu invocation, and Welcome
    pages are untested at runtime.** LaunchServices lists the service; `uitest` proves
    the handler and every settings page builds. The live Settings window has been checked;
    a tab-by-tab persistence review is still manual.
13. **The Welcome window is not auto-shown at launch.** It is deliberately menu/About-only
    so the Finder drag harness stays deterministic. If first-run auto-show is wanted, add
    an explicit opt-in and update the harness launch path.
14. **Launch at login may need approval** for an ad-hoc signed app. Settings alerts and
    reverts; test on the target Mac.
15. **Video redaction is one static rectangle for one time range.** There is no motion
    tracking, no multiple regions, and no per-frame boxes. Audio redaction is one range
    per pass; `cropVideo` remains a coordinate form, not a timeline.
16. **`convert` has no per-conversion parameters and ignores the format defaults.**
    `Convert.perform` receives empty params from the CLI, so headless output never matches
    what a drag produces. Use `tool` for quality/DPI/size controls.
17. **GZIP naming depends on input shape.** A single file becomes `<name>.gz`; a folder or
    multiple inputs become `<name>.tar.gz`. Extraction handles both.
18. **The fan preview in Welcome is capped at eight petals** (half scale) for readability;
    it is not the full tool set.
19. **The external harness does not exercise the media forms.** Its 12/12 run covers the
    drag path and the existing editors, not Redact Video/Audio or Audio to Video. Add a
    media scenario or run those forms manually before marking them fully exercised.

## Manual interaction test (remaining)

- Launch `Zest.app`. Confirm the wand-and-stars status item, no Dock icon, no window on
  launch.
- Open **Getting Started…** from the menu; step through all five pages. Confirm the fan
  previews are readable and the keycaps match the configured modifiers.
- Open **Settings**; change every popup, toggle sound/keyboard control, reopen, confirm
  persistence. Build every Formats page (the automated test does this; verify visually).
- Open **Preview Wheel** from the status menu; hover petals in the fan, tap
  Shift/Command/Control, close with Escape and by clicking outside.
- With a real Finder drag, tap **Command** then **Control** mid-drag; confirm the fan
  rebuilds to tools/actions while staying anchored. Release in the center and outside the
  wheel; both must cancel cleanly.
- Drag a PDF; test reorder, rotate, and extract-images forms. Split is automated.
- Actions: AirDrop, Float (drag-out to Finder, double-click to open), Copy, Move, Terminal,
  Reveal. Copy Path and Float row close are automated.
- Finder Services menu → **Convert with Zest**.
- Optional keyboard control: enable it, grant Accessibility to Zest itself, then test
  arrows, Return, Escape.
- Check `~/Library/Logs/Zest.log` for errors after the run.

## Feature surface

- Menu-bar-only, drag files in Finder, tap a modifier to arm a wheel:
  **Shift = formats**, **Command = tools**, **Control = actions**. The app default wheel
  is the matte graphite **fan** (amber selection); **rings** remains a Settings option.
- Format surface: images JPG/PNG/WebP/HEIC/TIFF/AVIF/BMP/GIF + PDF; video
  MP4/MOV/MKV/WebM/AVI/WMV/GIF; audio MP3/M4A/WAV/FLAC/OGG/Opus/AIFF/WMA; PDF→DOCX/
  PAGES/PPTX/XLSX/JPG/PNG/EPUB/TXT/MD; documents; spreadsheets; subtitles; archives
  ZIP/TAR/GZIP, RAR input via `unar` (present).
- Actions: AirDrop, Float, Copy, Move, Copy Path, Terminal, Reveal.
- Tools: compress/exact size, resize, crop, **Add BG**, rotate, flip, adjust, grayscale,
  annotate, redact, strip tags, metadata, collage, QR, **snapshots**, trim, split, join,
  speed, snapshot, GIF, mute, extract audio, normalize, bleep, **redact video**,
  **redact audio**, **audio→video**, channels, sample rate, PDF
  merge/split/reorder/rotate/extract images, **archive extract**.
- Settings: five tabs; per-format defaults; live compatibility matrix; folder shortcuts;
  engine status; launch at login; Float/Terminal behavior; wheel style; appearance;
  collision policy; keyboard control.
- Onboarding: five pages from the status menu / About.

## Invariants and gotchas

- **Never** call `NSApp.activate` on the drag path. The overlay must stay non-activating
  or the Finder drag is cancelled. Demo/Settings/Welcome paths may activate.
- The wheel anchors where the trigger was tapped, then **stays put**. Hovering is driven
  by drag coordinates; do not make the wheel follow the pointer.
- Read the drag pasteboard only while the left button is down; cache URLs at drag start.
- Keep `WheelView` as the drag destination. Do not add `NSDraggingDestination` overrides
  to `OverlayPanel`; AppKit does not expose them there.
- `OverlayPanel.cancelOperation` must route through `onCancel` so `OverlayController`
  clears state.
- Output naming goes through `Naming.output` / `Naming.batchOutput`; honour
  `Prefs.collisionPolicy`.
- All AppKit UI mutations go through `onMain`; conversion jobs run on a global queue.
- `HUDController.shared` must own exactly one panel. `dismiss()` must close the panel, not
  only drop the reference.
- Settings pop-ups and cards must be attached to their common ancestor before activating
  width constraints. The scroll document view must be assigned before
  `document.widthAnchor == scroll.contentView.widthAnchor` is activated. This caused two
  `NSGenericException` crashes; the `exerciseForTesting()` check is the regression guard.
- Settings scroll documents must stay flipped (`FlippedDocumentView`). A plain `NSView`
  document opens at the bottom of a taller page because AppKit uses a bottom-left origin.
  Keep the explicit tab widths; 88 pt truncates "Compatibility".
- Keep formats/tools truthful: gate on `Capability`/`ToolFinder`, hide what cannot run.
- **Every settings control needs a consumer.** A popup that writes a key no engine reads is
  worse than a missing popup: `imageCompression` is the existing example (see the settings
  audit). When adding a default, add it to `Prefs.conversionParams(for:)`, consume it in
  the engine, and cover it with a check.
- **Validate tools by execution, not existence.** `ToolFinder.resolve` runs the version
  flag with a 2 s timeout and caches the result; `build.sh` must apply the same probe
  before bundling. A present-but-trapping binary must never shadow Homebrew.
- Tool parameters cross as `[String: String]`. Editors store normalized geometry (0…1,
  top-left origin) and markup JSON, never raw preview pixel coordinates.
- `Shell.run` merges stdout/stderr and throws on non-zero; pass arguments as arrays, never
  build shell command strings except where explicitly quoted (gzip).
- `ZipUtil.zipDirectory` must put OOXML parts at the archive root; `COPYFILE_DISABLE=1`
  stays set.
- `DocxWriter`/`PptxWriter` must create every `_rels` directory they write into.
- Fixed-layout EPUB must keep `mimetype` first, one page image per XHTML page, and
  `<meta property="rendition:layout">pre-paginated</meta>` in the OPF. Do not move it
  into the flowing writer.
- `main.swift` must ignore Finder `-psn_…` arguments before dispatching to CLI.
- `build.sh` must brace variable expansions that touch non-ASCII text (`${APP}…`).
- The app icon comes from `Resources/AppIcon.icns`; `CFBundleIconFile` must stay in
  `Info.plist` and `build.sh` must copy the `.icns`. `AppIcon.image` is only a fallback.
- Keep `WheelView` drag handling callable from `FakeDragInfo`; `uitest` must not need a
  real `NSDraggingSession`.
- **Draw every non-empty surface as its own ring in ring mode.** `Catalog.surfaces(for:)`
  feeds `WheelView.surfaces`; the modifier only sets `emphasis`. Do not reintroduce a
  single-surface `choices` assignment for rings.
- **Fan mode rebuilds one ring on every emphasis change.** `emphasize` must special-case
  fan before checking `rings.contains`; otherwise a mode switch falls back to the current
  mode.
- **Petal paths stay closed and short.** Ring `wedgePath` outer arc counter-clockwise,
  inner arc clockwise. Fan `fanPetalPath` uses two shoulder cubics and elliptical caps in
  petal-local coordinates; it must start and end at the inner tip and close without a
  crossing. Do not replace it with a per-petal angular wedge.
- The `Wheel` log line must keep `mode`, `count`, `anchor`, `screen`, `choices` and must
  include `radius` and `outer`; the drag harness aims at `radius` and clamps with
  `outer + 14`. Fan logs one ring with `radius=130` and `outer=192` at scale 1.
- Ring labels must fit the wedge chord: `2 · midRadius · sin(step/2) − 12` at
  `WheelView.labelFont(for:in:)`. Do not shrink the radius or raise the font without
  re-running `uitest`.
- Fan labels are measured against the petal body, not the angular chord:
  `fanLabelFont` / `fanFormatFont` take `petal.labelWidth` from
  `FanPetalGeometry.halfWidth(at:)` and pick the largest size that fits. Re-render
  `Zest wheel --style fan --mode tools` after changing fan title lengths or petal
  geometry; `uitest` asserts the fit and the seam gaps — keep both green.
- **Respect the approved graphite-glass design** (see *Approved fan-wheel design*): no
  blue/violet/pink/teal accents, no neon or luminous coloured rims, no bright white
  outlines, no backdrop plate. The glass cues are the neutral, low-opacity ones listed
  in the palette — anything brighter or coloured is a regression. Fan colors live only
  in `drawFanPetalBody`, `drawFanPetalShadow`, `drawFanHub`, and `drawFanContent`.
- PDF compression must pass a per-page `kCGPDFContextMediaBox`; do not regress to one
  default box.
- PDF image extraction must keep native XObject pixels; use the page render only when a
  page has no image XObject.
- OCR is fallback-only: use PDFKit text when it exists, Vision only when it is empty.
- Video redaction converts the normalized rect to pixels once, clamps it to the frame, and
  rounds width/height down to even values for yuv420p. Keep the overlay filter's `enable`
  range aligned with the requested start/end; do not apply the box to the whole clip.
- `selftest` currently reports 93 checks and `uitest` reports 29; add a check whenever a
  converter, engine option, or UI path is added, and keep the structural verifiers.

## Coverage checklist

Legend: `[x]` = verified headlessly; `[~]` = automated in-process smoke (`uitest`) or
launch, but not a full physical interaction; `[ ]` = still needs a real interaction or
manual run. Do not promote a `[~]` row to `[x]` without the real drag or manual test.

- [~] Menu-bar app, no Dock icon, status item, Settings, demo wheel (status menu and
  settings construction verified; demo wheel manual)
- [~] Permission-free drag watcher, fan/ring wheel, drop-to-commit (external harness
  drives fan-mode Finder drags through Shift/Command/Control; mid-drag trigger switching
  manual)
- [x] **Fan wheel**: one surface, 384 pt petal flower (`fanInner 68`, `fanOuter 192`),
  no backdrop plate, graphite-glass petals with lit edges and subtle depth, muted amber
  selected petal, sentence-case icon + label content (no truncation at the compact
  size), dynamic hub with filename/format/size, mode rebuild. Verified through
  `Zest wheel` renders, `uitest` (seam separation + label fit), `selftest`, and the
  external harness (12/12).
- [~] **Settings**: compact 480×620 layout, custom orange pill tabs, flat cards,
  search/sidebar Formats, compatibility tables, Folders, centered About with **no
  unlock/free-trial UI**; all five tabs and every format page build (`uitest`), all five
  tabs have been rendered offscreen (`settings-preview`), and the live window confirms
  titlebar, traffic lights, corrected checkmarks, glass vibrancy, and the real About
  icon. Tab-by-tab persistence review remains manual.
- [~] **Welcome**: five pages build and are menu-accessible; page clicks/visuals pending
- [x] Image conversions (9 + PDF), WebP via cwebp, image tools — headless
- [x] Video/audio conversions + media tools — headless
- [x] **Add BG** — headless (square canvas + resampling)
- [x] **Archive extract tool** — headless (non-empty folder)
- [x] **Multi-frame snapshots** — headless (two files)
- [x] **Redact video** — headless black-box pixel assertion inside/outside the range
- [x] **Redact audio** — headless (tone range, ffprobe-readable output)
- [x] **Audio to video** — headless (ffprobe sees both streams)
- [x] PDF conversions and page operations — headless; OCR, embedded extraction, mixed
  page sizes
- [x] **Fixed-layout EPUB** — headless (page images + `pre-paginated` metadata)
- [x] Documents: PDF/DOCX/TXT/MD/RTF/HTML/EPUB — headless; flowing PDF layout checked
- [x] Spreadsheets: CSV/TSV/XLSX/ODS (PDF render) — headless
- [x] Subtitles: SRT/VTT/TXT + shift/merge — headless
- [x] Archives: ZIP/TAR/GZIP create/extract/convert — headless
- [~] Actions: Copy Path and Float row close verified by the harness; AirDrop, Float
  drag-out, Copy, Move, Terminal, Reveal manual
- [~] HUD progress, reveal-on-click (keepBoth/replace and the drag HUD verified;
  reveal-on-click manual)
- [x] `selftest` green (93) on the final graphite design
- [x] `uitest` green (29) — includes fan seam-separation and fan label-fit checks
- [x] External drag harness: 12 scenarios, **12/12 in one batch** on the final graphite
  bundle (2026-10-24). Isolated scenario flakes (a lost synthetic modifier, a first-run
  "did not arm") have occurred; rerun the scenario once before investigating.
- [~] Float panel: rows, per-row close, and panel close verified live; drag-out,
  double-click, and add-to-existing manual
- [~] Tool editors: crop, annotate, redact, metadata verified by the external harness;
  Add BG/Snapshots/Redact Video/Redact Audio/Audio to Video forms still need a visual
  check (the engine paths are covered by selftest and a shipping-bundle run)
- [~] **App bundle**: icon present, `CFBundleIconFile` set, ad-hoc signed, no broken tools;
  `build.sh` validates candidates and the About page loads the real icon. Rebuilt after
  the compact pass, launched, and harness-verified (log line `radius=130 outer=192`).
- [~] Finder Services: handler opens the wheel and LaunchServices lists
  `Convert with Zest` (`public.item` → `convertWithZest`); invoking it from the Finder
  menu is manual
- [ ] Keyboard control (Accessibility): arrows/Return/Escape (requires Zest TCC grant)
- [ ] Enter-on-selected-file in Finder (AX available; AXObserver not implemented)
- [ ] Pages output (requires `/Applications/Pages.app`; absent here)
- [ ] LibreOffice slides/legacy Office output (requires `soffice`; absent here)

## Resume checklist (in order)

0. **Commit the verified working tree** — `Overlay.swift`, `UITest.swift`, `CLI.swift`,
   `WelcomeWindow.swift`, `Harness/dragtest.swift`, this file. Everything is green on it
   (see *Current state*); nothing is committed yet.
1. **Orient on the surfaces.** `Catalog.swift` holds the format, tool and action tables;
   `Prefs.swift` the per-format defaults; `Settings.swift` every settings page. The local
   `RE/` folder is ignored by git and not needed for any of this.
2. **Rebuild the bundle after source changes.** `./build.sh`; confirm
   `Contents/Resources/AppIcon.icns` exists, the app is ad-hoc signed, and any
   `Contents/Resources/Tools` directory that remains contains only binaries that pass
   `-version`. An absent Tools directory is normal on this host: `ToolFinder` resolves
   Homebrew.
3. **Run the external harness.** `./Harness/run.sh all` (or one scenario). It needs
   Accessibility for the launching app, Finder on the main display, and a rebuilt
   `Zest.app` — run it as the user, never under `sudo`. Artifacts and failures land under
   `Zest/Harness/run/<scenario>/`. If a fan-mode scenario fails, first confirm the log
   line and slice radius before changing the drag logic;
   `defaults write com.zest.app wheelStyle rings` can isolate a fan regression. Always
   restore `wheelStyle fan` if that was the intended app default. Rerun a failed scenario
   once before treating it as a regression (see harness flake notes).
4. **Rerun the headless suites** after every code change: `<debug>/Zest selftest` and
   `uitest`.
5. **Manual UI pass:** open Settings and every tab, confirm the compact 480×620 layout,
   orange pill tabs, searchable format sidebar, and the About page has no unlock/trial
   UI. Then open Getting Started and step through all five pages, drag a file with the
   fan wheel, tap the modifier mid-drag, and test the Add BG / Extract / Snapshots /
   Redact Video / Redact Audio / Audio to Video forms.
6. **Remaining manual rows:** AirDrop, Float drag-out/double-click, Finder Services menu
   invocation, and keyboard navigation.
7. **Optional feature work** — see *Open issues*, especially fan pagination, image
   compression strength, app-wide glass, video redaction tracking, and the ExifTool
   orientation follow-up.
8. **Update this file** with what the harness and manual run proved.

## History

Everything below records decisions and defects. Current behaviour is documented above;
where history and source disagree, the source wins.

### Wheel evolution

- **Rings (the original layout, still current for that mode):** three concentric
  surfaces in a 576 pt disc (hub 72, outer 288), all visible, emphasis brightening one.
  Still available via Settings and still the `WheelView` default for headless geometry
  tests.
- **Compact wedge fan (superseded 2026-10-24):** hub 112 / outer 248, one surface,
  orange hover accent, uppercase labels, a dark rounded plate behind the fan. Replaced
  by petals.
- **Petal redesign:** the angular wedge became `FanPetalGeometry` teardrops (two shoulder
  cubics + elliptical caps, single source of truth for drawing, labels, and hit-testing).
  Went through several material iterations — grey glass, glowing multihue glass
  (pixel-sampled from an operator mock), which the operator then rejected.
- **Final (2026-10-24):** the graphite material with per-count chord fill, first at
  medium 84/240 radii, then compact 68/192 (~80% diameter) at the operator's request.
  The compact pass moved the label anchor to 0.73 of the petal length and laddered the
  label font to an 8 pt floor so no label truncates. A final pass added the smoked-glass
  cues (neck pooling, cap light pool, sheen, lit edges) at low opacity after the
  operator asked for a glass finish. The tangerine app
  (`/Applications/Tangerine.app`, report at `RE/TANGERINE.md`) was also evaluated as a
  design source — its flat charcoal wheel was considered and superseded by the
  operator's graphite mock; its tool inventory had already informed the Zest catalog.

### HISTORY: the petal-overlap defect and its fix

The original bottom overlap (Grayscale/Adjust visually merging) had two root causes, in
order:

1. **Wedge-fan era:** a shared angular gap of `min(0.058, step · 0.18)` between every
   pair left only ~6.5 pt clearance at the inner radius at 15 items; the 1 px stroke plus
   the 8 pt hover glow made the pair merge. No per-petal offsets existed to fix.
2. **Early petal era:** with shoulder controls `0.85 / 1.0` the width profile saturated
   by mid-length while the chord keeps growing linearly, so the neighbour gap bottomed
   out at ~1.9 pt around the middle of the petal even though neck and cap gaps looked
   healthy.

The fixes — both in shared geometry, never per-petal offsets — were the near-chord-
tracking shoulder controls (`0.46 / 0.58` today) and the per-count 0.85 chord fill with
the sparse-surface width cap. The mock that prompted the work itself shows the bottom
pair touching; Zest deliberately does not reproduce that. `uitest` now asserts seam
containment and a ≥ 4.5 pt model gap at every sampled radius, wrap boundary included.
The constants quoted here are historical; `Overlay.swift` is authoritative.

### HISTORY: repository hygiene and tool packaging

- Two commits landed on `main` and were pushed: `238089f` (fan wheel, settings,
  onboarding, app icon, media tools) and `7c35f8c` (docs). `6f154bf` was the original
  commit for that work; it carried `RE/` and named the reference app, so it was rewritten
  and force-pushed. Anyone who fetched before the rewrite still holds it locally; GitHub
  keeps the dangling object addressable by SHA until it garbage collects. Source comments
  no longer name the reference app — check with
  `git grep -in <name> -- . ':!RE'`; it must return nothing. `.gitignore` covers `RE/`
  and `Zest/Zest 2.app/`.
- **Tool bundling:** the reference app's bundled `ffmpeg` and `cwebp` both exit
  **133 (SIGTRAP)** on this host. They were copied once, shadowed
  `/opt/homebrew/bin/ffmpeg`, and made every media tool fail. This is why
  `ToolFinder.resolve` executes each candidate with its version flag (2 s timeout,
  cached) and why `build.sh` applies the same probe before bundling and deletes any
  bundled binary that fails. The current bundle ships **no** media tools. Never copy a
  third-party app's Tools directory.
- **App icon:** the bundle previously shipped no icon (an earlier claim here was wrong).
  `make-icon.swift` generates `AppIcon.icns`, `Info.plist` sets `CFBundleIconFile`,
  `build.sh` copies it, and `AppIcon.image` loads it with a repository-path fallback.
- `Zest settings-preview <tab 0-4> <out.png>` renders one Settings tab offscreen at 2×.
  It forces `.darkAqua` and temporarily hides the glass material because
  `NSVisualEffectView` does not cache cleanly into a bitmap; the titlebar/traffic lights
  do not appear in that render. Use the live window for chrome.
- The old four-direction mockup renderer and earlier wheel renders were temp files
  (`/tmp/…`, `…/T/opencode/…`) and may be swept at any time; they are not evidence.

## Style

Swift 5 language mode, AppKit programmatic UI, no storyboards, no third-party packages.
Keep shipped paths complete: unsupported operations must fail with a clear message and be
hidden from the wheel when the engine is absent. Update this file in the same session as
any architecture change.
