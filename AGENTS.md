# AGENTS.md — Zest

Handoff context for any future session working in this repository.

Last verified: **2026-10-23**. Read **Current state** and **Resume checklist** before touching code.

## What this is

**Zest** — a local-only, menu-bar file converter for macOS. Drag files in Finder, tap a
modifier, and pick a target from the wheel. This is a personal build, not a distribution.

- Project root: `Zest/`
- A commercial zero-click converter installed locally serves as the behavior reference and can
  seed the bundled media tools.
  - Reference bundle: `Contents/Resources/Tools/ffmpeg` and `cwebp`, ExifTool scripts, a Pages
    template.
  - Menu-bar app (`LSUIElement`), 275 conversion options, 26 tools, 6 actions.
- No network, no uploads, no telemetry, no third-party Swift packages.

## Current state

- **Debug compiles clean.** `swift build`: zero errors, zero warnings.
- **Release bundle is current.** `./build.sh` rebuilt `Zest.app` on 2026-10-23, bundled
  `Contents/Resources/Tools/ffmpeg` and `cwebp`, and ad-hoc signed it.
- **Headless suite green.** **83 passed · 0 failed · 0 skipped** in debug.
- **UI smoke suite green.** **25 passed · 0 failed** via `Zest uitest`. It exercises the
  three-ring wheel (every slice in every ring hit-tests, every label fits its wedge, hover,
  ring-aware drops, keyboard stepping across rings), overlay anchoring and emphasis switching,
  the drag watcher (including the disarm grace period), planner batch routes, HUD lifecycle,
  Float rows, Settings construction, the Services handler, the status menu, and Copy Path. It
  does not post mouse events or enter Finder.
- **Wheel shows every surface at once.** Formats, tools, and actions are three concentric rings
  in one wheel; the trigger modifier only brightens the ring it names. The previous wheel drew
  one surface and painted its wedges with arcs that swept the long way round, so it rendered as
  a solid black disc with two visible labels. Both defects are fixed (2026-10-23).
- **External drag harness: 12 scenarios, gate passed.** `Zest/Harness/dragtest.swift` drives
  Finder with AX and synthetic events and verifies outputs structurally. On 2026-10-23 two
  consecutive full runs on the three-ring wheel passed 12/12 (basic, tools, actions, folder,
  twopdf, pdfsplit, crop, markup, redact, metadata, collision, float).
- **App launches.** The bundle logs
  `options=616 tools=58 ffmpeg=…/Contents/Resources/Tools/ffmpeg`.
- **Accessibility is available to the automation host** (`AXIsProcessTrusted() == true`), so
  Finder AX queries and synthetic `CGEvent` mouse drags work. Screen Recording is still denied
  (`screencapture` fails); verify with output files and `~/Library/Logs/Zest.log`, not screenshots.
- **Harness limitation:** a synthetic `.flagsChanged` posted mid-drag is not reliably re-targeted
  by the window server, so the harness presses the trigger before the first drag step. Mid-drag
  mode switching is covered in-process by `uitest`; the real modifier tap still needs one manual
  pass.
- **Remaining manual rows:** AirDrop, Float drag-out and double-click, Finder Services menu
  invocation (registration is confirmed in LaunchServices), and optional keyboard navigation
  (needs Accessibility for Zest itself).
- **Tracked on GitHub.** Public repo at <https://github.com/shin0biX/zest>; `main` tracks
  `origin/main`. Build outputs and harness artifacts are ignored.

### Verification snapshot

```sh
cd Zest
swift build                       # clean (debug)
.build/debug/Zest selftest        # 83 passed · 0 failed · 0 skipped
.build/debug/Zest uitest          # 25 passed · 0 failed
./build.sh                        # release + Zest.app + tools + ad-hoc sign
./Harness/run.sh all              # external Finder drags, 12 scenarios
open Zest.app                     # launch + log
```

Do not mark an interaction row as fully tested without the real drag or the manual run.

## Resume checklist (in order)

1. **Rebuild the bundle after source changes.** `./build.sh`; confirm
   `Contents/Resources/Tools/ffmpeg` and `cwebp` exist and the app is ad-hoc signed.
2. **Run the external harness.** `./Harness/run.sh all` (or one scenario). It needs Accessibility
   for the host, Finder on the main display, and a rebuilt `Zest.app`. Artifacts and failures land
   under `Zest/Harness/run/<scenario>/`. Multi-file selection uses Cmd+A in a clean scenario
   folder; if `twopdf` fails on selection, check Finder focus before changing the drag logic.
3. **Rerun the headless suites** after every code change: `<debug>/Zest selftest` and `uitest`.
4. **Run the remaining manual rows**: AirDrop, Float drag-out/double-click, Finder Services menu
   invocation, and keyboard navigation; collision naming is keepBoth/replace only.
5. **Optional feature work** — see *Remaining gaps and known limits*.
6. **Update this file** with what the harness and manual run proved.

### External drag harness

Synthetic events work because the automation host is trusted. The harness is a standalone binary
(`Zest/Harness/dragtest.swift`) built by `Harness/run.sh`; it never links Zest's code and lives
outside the shipping sources. It runs twelve scenarios:

| Scenario | Path exercised |
| --- | --- |
| `basic` | PNG → JPG through the Shift wheel |
| `tools` | PNG → Grayscale through Command → tools |
| `actions` | PNG → Copy Path through Control → actions |
| `folder` | folder → ZIP through the Shift wheel |
| `twopdf` | two selected PNGs → one two-page PDF |
| `pdfsplit` | three-page PDF → Split form → Apply → three one-page PDFs |
| `crop` | Crop editor → drag 30–70% → Crop → ~512×320 PNG |
| `markup` | Annotate editor → drag a box → Save → red stroke in the pixels |
| `redact` | Redact editor → drag a box → Redact → black fill in the pixels |
| `metadata` | Metadata editor → Title/Author fields → Save → TIFF/PNG tags |
| `collisions` | keepBoth makes `dup 2.jpg`; replace rewrites `dup.jpg` |
| `float` | two files → Float panel → row close → header close |

Mechanics:

- Find the Finder icon: activate Finder, read the browser window by title (AXDocument is often
  nil), ensure icon view through the `AXRadioButton` described `icon view`, then the `AXImage`
  whose `AXFilename` matches. Click with `AXPosition` + half of `AXSize`.
- For a multi-file selection, click the first icon, then send Cmd+A. Scenario folders contain only
  the inputs, so select-all is exact. `AXSelectedChildren` and synthetic shift-clicks race with
  Finder's activation selection; a click-first AX retry was tried and made the count worse.
- AX coordinates are top-left; AppKit is bottom-left. Convert with `screenHeight - y` before
  comparing with Zest's log.
- Post mouse-down, then press the trigger, then drag. **A synthetic `.flagsChanged` sent mid-drag
  is not reliably re-targeted by the window server** and drops the drag; press the modifier
  between mouse-down and the first drag step. `uitest` drives mid-drag mode switching in-process.
- Parse the newest `Wheel mode=… anchor=x,y screen=WxH radius=… outer=… rings=… choices=id,id,…`
  line. `mode` names the emphasized ring, `choices` are that ring's ids, `radius` is its mid
  radius, and `outer` is the disc radius. Slice 0 is centered at the top:
  `step = 2π/count`, `start = π/2 + step/2`, `angle = start - (index+0.5)·step`. Convert the
  AppKit wheel point to CG top-left coordinates.
- Drag to the slice, mouse-up, release the modifier, and wait for the latest `Choice <id>` line.
- Tool windows: the AX frame minus the known content height gives the title bar; the canvas is
  the top `582` pt (crop) or `668` pt (markup) of the content. Replicate the centered image rect,
  drag between normalized points, then press the window's button by AX title.
- Metadata: find the alert by static text, set the first two `AXTextField`s (Title, Author), press
  **Save**. PNG keeps the TIFF description and artist.
- Collisions: write `defaults write com.zest.app collision keepBoth|replace` and wait ~0.6 s; a
  running Zest picks the value up through cfprefsd. Always restore `keepBoth`.
- Float: find the borderless panel by its static text, then click the close buttons by geometry
  (header close at `maxX-21, minY+21`; first row at `+72`, second at `+134`). The title does not
  change when rows close; assert on row names, not the header count.
- Finder occasionally ignores a synthetic press. The harness re-selects the icon and retries the
  drag up to three times; crop also retries once if the Crop button stays disabled. Icon centers
  are read only after Finder's layout is stable, and the drag pasteboard is checked against the
  intended file name so a rearranged icon cannot silently drag the wrong file.
- Verify structurally (ImageIO reload, page count, archive listing, tag values, red-pixel count,
  black-pixel count). There are no screenshots to fall back on. Artifacts land in
  `Zest/Harness/run/<scenario>/`.

### Manual interaction test (remaining)

- Launch `Zest.app`. Confirm the wand-and-stars status item, no Dock icon, no window on launch.
- Open **Settings**; change every popup, toggle sound/keyboard control, reopen, confirm persistence.
- Open **Preview Wheel** from the status menu; hover slices in all three rings, tap
  Shift/Command/Control to move the emphasis, close with Escape and by clicking outside.
- With a real Finder drag, tap **Command** then **Control** mid-drag; confirm the emphasis moves
  to tools/actions while every ring stays visible and the wheel stays anchored. Release in the
  center and outside the wheel; both must cancel cleanly. (The harness cannot do this reliably;
  `uitest` covers the logic.)
- Drag a PDF; test reorder, rotate, and extract-images forms. Split is automated.
- Actions: AirDrop, Float (drag-out to Finder, double-click to open), Copy, Move, Terminal, Reveal.
  Copy Path and Float row close are automated.
- Finder Services menu → **Convert with Zest**. LaunchServices already lists the service; if it
  is missing from the menu, relaunch Finder or call `NSUpdateDynamicServices`.
- Optional keyboard control: enable it, grant Accessibility to Zest itself, then test arrows,
  Return, Escape.
- Check `~/Library/Logs/Zest.log` for errors after the run.

## Architecture

### Source tree (22 app Swift files + harness)

```
Zest/
  Package.swift
  build.sh
  Resources/Info.plist
  Sources/Zest/
    main.swift          App.swift           Support.swift       Prefs.swift
    Catalog.swift       DragWatcher.swift   Overlay.swift       HUD.swift
    Planner.swift       KeyTap.swift        ImageEngine.swift   PDFEngine.swift
    MediaEngine.swift   TextTools.swift     OfficeWriters.swift DocEngine.swift
    SubtitleArchive.swift                   Tools.swift         ToolUI.swift
    Floating.swift      CLI.swift           UITest.swift
  Harness/
    dragtest.swift      run.sh              # external Finder drag harness
  Zest.app              # build output
```

| File | Role |
| --- | --- |
| `main.swift` | CLI dispatch for real arguments; otherwise `NSApplication` + `AppDelegate`. Ignores Finder `-psn_…` arguments. |
| `App.swift` | App delegate, status item, Services provider, Settings window, demo wheel, engine status. |
| `Support.swift` | `Shell`, `ToolFinder`, `Kind`, `KindDetector`, `Naming`, `Bytes`, `Temp`, `Log`, `MediaProbe`, `onMain`/`onMainSync`, `ZestError`. |
| `Prefs.swift` | Suite `com.zest.app`, trigger keys, quality, collision policy, sound, keyboard control, `Capability`, ImageIO encode probe. |
| `Catalog.swift` | Format tables, tool/action tables, per-kind wheel choices, option counts. |
| `DragWatcher.swift` | Permission-free drag detection: `pressedMouseButtons`, modifier transitions, `NSPasteboard(name: .drag)`. |
| `Overlay.swift` | Non-activating full-screen `OverlayPanel`, radial `WheelView` with three concentric surfaces (formats outer, tools middle, actions inner), drag destination, keyboard stepping, demo asset. |
| `HUD.swift` | Exactly one floating progress panel; `HUDController.shared`; reveal-on-click. |
| `Planner.swift` | Routes committed choice → conversion/tool/action; batch image→PDF; HUD and alerts. |
| `KeyTap.swift` | Optional CGEventTap for keyboard navigation (Accessibility). |
| `ImageEngine.swift` | ImageIO encode/decode; `ImageOps` crop/resize/rotate/flip/adjust/grayscale/markup; SVG rasterization; WebP via `cwebp`. |
| `PDFEngine.swift` | Render pages; images→PDF; PDF→DOCX/PPTX/XLSX/EPUB/TXT/MD/RTF; merge/split/reorder/rotate/compress/extract/QR/metadata. |
| `MediaEngine.swift` | ffmpeg/ffprobe conversions, media tools, metadata mapping; **also defines `Convert` dispatcher at the bottom**. |
| `TextTools.swift` | CoreText paginated PDF, RTF, HTML/Markdown, `DocxReader`/`DocxWriter`, `EpubWriter`, `ZipUtil`. |
| `OfficeWriters.swift` | Minimal `PptxWriter`, `XlsxWriter`, `OdsWriter`, `SheetReader` (XLSX/ODS/CSV/TSV). |
| `DocEngine.swift` | Documents/EPUB/Pages/slides; `SheetEngine`, table-to-PDF. |
| `SubtitleArchive.swift` | SRT/VTT parse/write/shift/merge; zip/tar/gzip create/extract/convert. |
| `Tools.swift` | `ToolRunner` for every tool id; image compression search, metadata, collage, QR. |
| `ToolUI.swift` | Generic NSAlert forms, crop/markup editors, metadata editor, QR panel. |
| `Floating.swift` | Float action panel: retained non-activating panel, thumbnails, per-row close, drag-out. |
| `CLI.swift` | Headless `formats`, `convert`, `tool`, `selftest`, `uitest`; initializes `NSApplication.shared` without entering the run loop; owns the 83-check engine suite. |
| `UITest.swift` | `Zest uitest`: 25-check in-process UI smoke suite; `FakeDragInfo` drives `WheelView.performDragOperation` without a real drag session. |
| `Harness/dragtest.swift` | Standalone external harness. Finder AX + CGEvent drags through the real bundle, verifies outputs structurally. Scenarios: basic, tools, actions, folder, twopdf, pdfsplit, crop, markup, redact, metadata, collisions, float. |
| `Harness/run.sh` | Builds `dragtest` into `.build/harness/` and runs it (`all` or one scenario, `--keep-running` to reuse Zest). |

### Routing notes

- Drag flow: `DragWatcher` → `OverlayController.show` → `WheelView` (drag destination) →
  `Planner.submit`. The wheel anchors where the trigger was pressed and does not follow the mouse.
- **Every surface is drawn at once.** `Catalog.surfaces(for:)` returns the non-empty surfaces in
  formats → tools → actions order; `WheelView` lays them out as concentric rings whose thickness
  is `(outerRadius - hubRadius) / surfaceCount`. `emphasis` only brightens the ring named by the
  trigger modifier; it never removes a ring. A commit carries the ring's mode, not the armed one.
- **Wedge arcs must never sweep the long way round.** `wedgePath` runs the outer arc
  counter-clockwise from the lower to the higher angle and the inner arc back clockwise. The old
  version inverted both flags, painted the whole annulus per slice, and buried every label.
- Ring geometry is `WheelView.outerRadius` (340) and `WheelView.hubRadius` (84); hit-testing picks
  the ring by radius, then the slice by angle. `WheelHit` is `(ring, index)`; keyboard stepping
  walks the flattened ring order.
- **Drag handlers live on `WheelView`, not `OverlayPanel`.** `NSWindow`/`NSPanel` does not expose
  overridable `NSDraggingDestination` methods, and a plain view receives the events reliably.
  Do not move them back to the panel.
- `OverlayPanel.cancelOperation` calls an `onCancel` closure so controller state is cleared; it
  must not close the window directly.
- No `NSApp.activate` on the drag path. The overlay is `.nonactivatingPanel`; activating cancels
  the Finder drag. Demo/Settings paths may activate.
- `HUDController.shared` owns one panel. `FloatingFiles` retains one panel per Float invocation.
- Batch routing: images→single PDF in `Planner`; folder/multiple archives in `Planner`; batch tool
  ids (`join`, `merge`, `collage`) in `Planner` + `ToolRunner.isBatch`.
- `Convert.perform(_:to:params:)` is at the bottom of `MediaEngine.swift`; there is no
  `Convert.swift`.
- CLI uses the same engines as the app. It initializes `NSApplication.shared` first but never
  enters the run loop.
- `DragWatcher.process(flags:pressed:change:)` is the testable seam: the timer samples
  `NSEvent.pressedMouseButtons`, modifier flags, and the drag pasteboard change count, then calls
  it. `uitest` drives the seam directly; do not test by sleeping on the timer.
- Overlay logging is load-bearing for the external harness: `Wheel mode=… count=… anchor=x,y
  screen=WxH radius=… outer=… rings=… choices=id,id,…` on every arm and mode switch, and
  `Choice <id> mode=…` on commit (`Choice cancel` on cancel), where the commit's mode is the ring
  the choice came from. `mode`, `choices`, and `radius` describe the emphasized ring; `rings`
  lists every visible surface. Drag diagnostics (`Drag start`, `Drop enter`, `Drop perform`,
  `Wheel disarm …`) are additive; keep the `Wheel`/`Choice` formats stable or update the harness.
- `Zest wheel <out.png> [--kind …] [--mode …] [--hover N]` renders the wheel offscreen at 2×.
  It is the only visual check available: Screen Recording is denied, so screenshots are not.
- `DragWatcher.scheduleDisarm` keeps the wheel alive for 0.22 s after mouse-up. `OverlayController.
  handleDisarm` then closes immediately if the pointer is outside the wheel, or waits up to 1 s
  for `performDragOperation` if the pointer is on it. Do not return to closing at mouse-up.

## Build and run

```sh
cd Zest
swift build                       # debug, for quick engine work
./build.sh                        # release bundle, tools, ad-hoc signature
open Zest.app
```

- Bundle id: `com.zest.app`; settings live in that UserDefaults suite.
- Logs: `~/Library/Logs/Zest.log`.
- Ad-hoc signing is sufficient; no developer identity.
- Debug binary: `.build/debug/Zest`. Release binary: `.build/release/Zest`.
- `build.sh` bundles media tools (ffmpeg, cwebp) into the app. It uses `ZEST_TOOLS_SRC` when
  set, otherwise the first `/Applications/*.app/Contents/Resources/Tools` that contains both
  binaries; `Resources/Tools/` is copied over either. Without them, tools fall back to
  Homebrew/PATH.

### Headless usage

```sh
.build/release/Zest formats sample.png
.build/release/Zest convert sample.png --to pdf
.build/release/Zest tool compress sample.png --params percent=50
.build/release/Zest tool metadata sample.jpg --params remove=1
.build/release/Zest tool qr sample.png
.build/release/Zest selftest
.build/release/Zest uitest
.build/release/Zest wheel /tmp/wheel.png --kind image --mode tools
```

`convert` accepts multiple files for images→PDF. `tool` accepts repeated `key=value` pairs after
`--params`; JSON values must be shell-quoted. `selftest` and `uitest` exit non-zero on any failure.
`uitest` runs in-process: it creates windows, drives the wheel and planner, and closes them; it
does not need Accessibility, Screen Recording, or a Finder session. `wheel` renders the current
wheel for a kind to PNG at backing scale; use it to inspect slice geometry and label fit.

## Selftest coverage

Samples synthesized in a temp root: PNG ×2, MP4 ×2, WAV, TXT, PDF ×2, DOCX, XLSX, CSV, SRT ×2,
ZIP. The suite runs 83 checks:

- Images: PNG→JPG/WebP/HEIC/AVIF/TIFF/BMP/GIF/PDF, two images→one PDF, resize, crop, rotate,
  flip, adjust, grayscale, compress, annotate, strip metadata, collage.
- PDF: →JPG/PNG/TXT/MD/DOCX/PPTX/XLSX/EPUB/RTF; merge, split, reorder, rotate, extract images,
  extract an embedded image at native size, mixed-page-size compression, compress, strip metadata;
  scanned PDF→TXT through Vision OCR.
- Documents: TXT→PDF/DOCX/RTF/HTML/EPUB, DOCX→PDF/TXT, Markdown→HTML/PDF, DOCX metadata strip.
- Sheets: CSV→XLSX/ODS/PDF, XLSX→CSV/ODS/PDF, ODS→CSV.
- Subtitles: SRT→VTT/TXT, shift, merge.
- Archives: extract, ZIP→TAR, folder→ZIP, TXT→GZIP, folder→GZIP→extract.
- Media (when ffmpeg is available): MP4→MOV/MP3/GIF, WAV→FLAC, trim, split, join, speed,
  snapshot, GIF, mute, extract audio, normalize, bleep, channels, sample rate, compress,
  metadata strip.

The eleven checks added beyond the original 72 are the five extra image encodes (HEIC, AVIF, TIFF,
BMP, GIF), scanned PDF→TXT OCR, native-size embedded image extraction, mixed-page-size compression,
TXT→GZIP, folder→GZIP→extract, and PDF split naming pages from the source stem.

Outputs are verified structurally, not just by size: `PDFDocument` must open with pages; OOXML
must have `[Content_Types].xml` at the archive root; EPUB/ODS must have `mimetype` at the root;
archives must not contain `__MACOSX`; images must reload through ImageIO; media must pass
`ffprobe` when it is available. The compression check compares page boxes before and after. The
embedded-image check asserts the extracted pixel size matches the XObject, not the page render.

If you add an engine or converter, add a selftest check in the same session. The count is expected
to grow; do not weaken structural verification to keep the count stable.

## UI smoke suite (`Zest uitest`)

`UITest.swift` runs 25 checks in-process and needs no TCC permissions:

- Catalog: every kind × mode has choices; the source format is not offered; tool ids are unique;
  no choice appears on two surfaces of the same wheel.
- Wheel: every slice in every ring hit-tests to its choice; hub/outside cancel; every title fits
  the chord of its wedge at the drawn font; hover follows rings and clears in the hub; a
  `FakeDragInfo` drop on the tools ring commits the choice and reports `.tools`.
- Overlay: opens at the anchor, moving through convert/tools/actions only changes emphasis and
  keeps all three rings, Escape closes, arrows step across rings and Return commits with the
  hovered ring's mode.
- DragWatcher: Shift arms after the drag pasteboard changes and release disarms after the grace
  period; a new drag cancels a pending disarm; Command then Control then Shift switches modes in
  order.
- Planner: image→JPG beside the source, two images→one 2-page PDF, folder→ZIP with contents.
- Naming: `keepBoth` produces `photo 2.png`; `replace` reuses `photo.png`.
- HUD: one panel, success and failure text, dismiss actually closes it.
- Float: panel appears with both file rows.
- Settings: window builds and pop-ups reflect `keepBoth` and `replace`.
- Services: `convertWithZest` opens the wheel with one image and the right kind.
- Status item: icon, Preview Wheel, Settings…, Quit are present.
- Actions: Copy Path writes the clipboard.

Limits: no synthetic mouse events, no Finder drag session, no AirDrop, no modal tool editors, no
Float drag-out/double-click, no menu tracking. The external harness covers Finder drags, the
crop/annotate/redact/metadata editors, PDF Split, keepBoth/replace, and Float row close; AirDrop,
Float drag-out/double-click, and menu tracking remain manual.

## Resolved compile ledger (2026-10-22)

The tree now builds clean. These were the blockers, kept for context.

| Issue | Resolution |
| --- | --- |
| `HUDController` had no `shared` | Added `static let shared` plus a private initializer. |
| `Convert.perform(input:to:)` label mismatch | Call `Convert.perform(url, to: fmt)`. |
| `FloatingFiles` missing | Added `Floating.swift` with a retained non-activating panel. |
| `CLI` missing | Added `CLI.swift` with formats/convert/tool/selftest. |
| `OverlayController.handleKey` missing | Added `handleKey(_ code: UInt16) -> Bool`, wired to `WheelView.step` and commit/cancel. |
| `ToolFinder.invalidate` missing | Added cache invalidation under the lock. |
| `UTType` unresolved in `Prefs.swift` | Imported `UniformTypeIdentifiers`. |
| `OverlayPanel` drag overrides invalid | Drag destination moved to `WheelView`; panel keeps only key/main overrides. |
| Dead `ModalHandler` in crop editor | Removed; added `ModalCloser` window delegate that stops the modal loop on close. |
| `NSBezierPath.addLine` invalid | Replaced with `line(to:)` in wheel and markup preview. |
| `PDFEngine` stray `i`, `Substring.trimmed`, `var best` | Removed the stray line; wrapped tokens in `String(...)`; changed to `let best`. |
| `DocxWriter`/`PptxWriter` wrote into missing `_rels` dirs | Create `word/_rels`, `slideMasters/_rels`, `slideLayouts/_rels` before writing. Found by selftest setup. |
| `build.sh` treated `$APP…` as a variable name | Use `${APP}…` before non-ASCII characters. |

## Semantic gaps fixed

1. **PDF routing.** `ToolUI.collect` now branches on PDF first for `split`, `reorder`, and
   `extractImages`; duplicate/unreachable cases were removed. Generic `rotate` handles both media
   and PDF pages.
2. **Multiple images → one PDF.** `Planner` routes an all-image batch with `fmt.outKind == .pdf`
   through `PDFEngine.fromImages` once, with a batch output name.
3. **Markup widths and fills.** Normalized widths are multiplied by image width (`max(1, width*W)`),
   arrowheads use `max(10, width*4)`, rectangles fill only when the op says `fill: true`, and text
   baseline matches the preview anchor.
4. **Media metadata mapping.** `MediaEngine.mapMetadataKeys` maps title/author/description/
   subject/copyright and drops unsupported tags before ffmpeg. PDF metadata uses PDFKit keys.
5. **OOXML/EPUB archive root.** `ZipUtil` writes parts at the root; `Shell` sets
   `COPYFILE_DISABLE=1`. Selftest asserts the root layout and absence of `__MACOSX`.
6. **QR with no codes.** `Planner` reports a "No codes found" HUD outcome instead of a silent
   success with no outputs.
7. **RTF conversion.** `attributed(text)` is computed once.
8. **Document metadata editor.** Non-editable documents present **Remove Metadata** as the primary
   action and explain the limitation in the message.
9. **Archive→archive location.** `ArchiveEngine.convert` writes the new archive beside the source
   using `Naming.output`, not into the temp extraction directory.
10. **Dropped `_rels` directories and modal-loop close behavior** are covered above.
11. **Settings crash on open.** `convertPopup`, `toolsPopup`, `actionsPopup`, `collisionPopup`,
    and `qualityPopup` were used by `syncControls()` before assignment, so opening Settings hit an
    implicitly unwrapped nil. All five are now created before the first sync.
12. **HUD dismissal leaked its panel.** `dismiss()` cleared the controller's reference but left
    the floating window visible. It now calls `panel?.close()`.
13. **PDF compression clipped non-Letter pages.** `buildCompressed` opened the context with one
    default box. It now passes per-page `kCGPDFContextMediaBox` from `pageRef` and falls back to
    the default only when a page has no `pageRef`. Compression still rasterizes.
14. **PDF image extraction rendered pages.** `extractImages` now walks image XObjects through the
    page resources, draws each at native pixel size, and renders a page only when it has no
    embedded image.
15. **Scanned PDFs produced empty text.** `VisionOCR.text(from:)` runs Vision's accurate text
    recognizer on a 220 dpi page render when PDFKit returns no text; `textPages` uses it as fallback.
16. **`.tar.gz` extracted to a bare tar file.** `ArchiveEngine.extract` now gunzips and then
    untars when the decompressed name ends in `.tar`; `.tgz` uses `tar -xzf`.
17. **Folder→GZIP moved the output onto itself.** The gzip step produced `<name>.tar.gz` while
    the requested output was `<name>.gz`; the move is skipped when the two standardized URLs match.
18. **UI coverage and drag diagnostics.** Added `uitest` and the `DragWatcher.process` seam; the
    overlay now logs the wheel anchor, screen, choices, and committed choice for the external
    harness.
19. **Split PDFs could collide with the source name.** `PDFEngine.split` now picks a stem whose
    `<stem>-page-N.pdf` outputs do not exist, unless the collision policy is `replace`.
20. **Mouse-up could close the wheel before the drop.** `DragWatcher` disarms after a 0.22 s grace
    period; `OverlayController.handleDisarm` then closes immediately outside the wheel or waits up
    to 1 s for `performDragOperation` when the pointer is on it.
21. **The wheel drew as a black disc and hid two thirds of the catalog.** `wedgePath` passed
    `clockwise: true` to the outer arc and `clockwise: false` to the inner arc, so each slice
    swept `2π - step` and every later fill buried the previous labels; the snapshot showed one
    black disc with two labels. The arcs now run the short way. The wheel also renders formats,
    tools, and actions as three concentric rings at once (`Catalog.surfaces`), so the modifier
    keys only emphasize a ring instead of hiding the other two. A regression check measures every
    title against its wedge chord, and `Zest wheel` renders the result to PNG.

## Remaining gaps and known limits

1. **The mid-drag modifier tap is not machine-verified.** The external harness presses the
   trigger between mouse-down and the first drag step because macOS does not reliably re-target a
   synthetic drag to a panel that appears mid-session. `uitest` covers the drag-watcher logic; one
   manual drag with a real Shift/Command/Control tap is still required.
2. **PDF compression still rasterizes.** Text, links, annotations, and form fields are lost.
   Per-page media boxes are now preserved, so mixed page sizes are no longer clipped, but
   compression remains image-based.
3. **Embedded image extraction has a fallback.** Only image XObjects are pulled at native size.
   Inline images, stencil masks, and pages with no image XObject render the whole page at the
   requested DPI. A reused image appears once per page.
4. **OCR is a fallback, not document reconstruction.** `VisionOCR` runs only when PDFKit returns
   no text. It recognizes printed text on a 220 dpi render; layout, tables, columns, and images are
   not rebuilt, and recognition quality depends on the scan. There are no language or accuracy options.
5. **DOCX reading is plain text.** `DocxReader` extracts `<w:t>` runs; DOCX→PDF/TXT/MD drops
   styling, tables, and images. Native `DocxWriter` output is intentionally minimal.
6. **SVG fallback quality depends on the host.** `rsvg-convert` is preferred; this Mac does not
   have it, so `qlmanage -t` is used.
7. **`ffprobe` is not bundled.** The bundle ships `ffmpeg` and `cwebp`; `ffprobe` resolves from
   Homebrew/PATH. Media probing and some media tool forms depend on it.
8. **Pages/Keynote/Numbers and LibreOffice outputs remain unavailable.** Pages output requires
   `/Applications/Pages.app`; slide/legacy Office output requires `soffice`. Options are gated.
9. **Enter-on-selected-file in Finder is deferred.** Accessibility is now available, so this is
   feasible, but no AXObserver path exists yet.
10. **Keyboard navigation requires Accessibility for Zest itself** and is optional; the mouse path
    must stay permission-free.
11. **AirDrop, Float drag-out/double-click, and the Services menu invocation are untested at
    runtime.** The external harness drives crop, annotate, redact, and metadata forms;
    LaunchServices lists the `Convert with Zest` service with `public.item` input, and `uitest`
    proves the handler opens the wheel. AppKit menu tracking, sharing pickers, and drag-out
    sessions are not simulated.
12. **`convert` has no per-conversion parameters.** Use `tool` for quality/DPI/size controls.
13. **GZIP naming depends on input shape.** A single file becomes `<name>.gz`; a folder or multiple
    inputs become `<name>.tar.gz`. Extraction handles both; UI text should keep saying so.

## Engine policy

- **Images:** ImageIO native (JPEG/PNG/HEIC/AVIF/TIFF/BMP/GIF/PDF). WebP encode via `cwebp`
  (ImageIO WebP encode is false). SVG via `rsvg-convert`, falling back to `qlmanage -t`.
- **Video/audio:** ffmpeg + ffprobe via `ToolFinder` (bundle first, then Homebrew/PATH). GIF palette
  filter, exact-size bitrate search, concat with `anullsrc` for silent clips, metadata key mapping.
- **PDF:** PDFKit/CoreGraphics; PDFKit text extraction with Vision OCR fallback; embedded image
  XObjects at native size; 300 dpi page rendering by default; per-page media boxes when compressing.
- **Documents:** `textutil` for legacy/RTF/DOCX interchange; native `DocxWriter`; CoreText
  pagination. WebKit deliberately not used.
- **Office:** native CSV/TSV/XLSX/ODS readers/writers; LibreOffice (`soffice --headless
  --convert-to`) only when installed for legacy/Apple formats. Gate options on capability.
- **Archives:** `ditto`/`zip`/`tar`/`gzip`; `.tar.gz` gunzips then untars; RAR input needs
  `unar`/`unrar`; 7z needs `7zz`.
- **Availability on this Mac:** bundled ffmpeg/cwebp; Homebrew ffprobe, cwebp, sips, textutil,
  qlmanage, zip, tar, gzip. Missing: ImageMagick, pandoc, rsvg-convert, 7z, unrar, LibreOffice,
  Pages/Keynote/Numbers.

## Invariants and gotchas

- **Never** call `NSApp.activate` on the drag path. The overlay must stay non-activating or the
  Finder drag is cancelled. Demo/Settings paths may activate.
- The wheel anchors where the trigger was tapped, then **stays put**. Hovering is driven by drag
  coordinates; do not make the wheel follow the pointer.
- Read the drag pasteboard only while the left button is down; cache URLs at drag start.
- Keep `WheelView` as the drag destination. Do not add `NSDraggingDestination` overrides to
  `OverlayPanel`; AppKit does not expose them there.
- `OverlayPanel.cancelOperation` must route through `onCancel` so `OverlayController` clears state.
- Output naming goes through `Naming.output` / `Naming.batchOutput`; honour
  `Prefs.collisionPolicy`.
- All AppKit UI mutations go through `onMain`; conversion jobs run on a global queue.
- `HUDController.shared` must own exactly one panel. `dismiss()` must close the panel, not only
  drop the reference.
- Settings pop-ups (`convertPopup`, `toolsPopup`, `actionsPopup`, `collisionPopup`,
  `qualityPopup`) must be assigned before `syncControls()` or Settings crashes on open.
- Keep formats/tools truthful: gate on `Capability`/`ToolFinder`, hide what cannot run.
- Tool parameters cross as `[String: String]`. Editors store normalized geometry (0…1,
  top-left origin) and markup JSON, never raw preview pixel coordinates.
- `Shell.run` merges stdout/stderr and throws on non-zero; pass arguments as arrays, never build
  shell command strings except where explicitly quoted (gzip).
- `ZipUtil.zipDirectory` must put OOXML parts at the archive root; `COPYFILE_DISABLE=1` stays set.
- `DocxWriter`/`PptxWriter` must create every `_rels` directory they write into.
- `main.swift` must ignore Finder `-psn_…` arguments before dispatching to CLI.
- `build.sh` must brace variable expansions that touch non-ASCII text (`${APP}…`).
- Keep `WheelView` drag handling callable from `FakeDragInfo`; `uitest` must not need a real
  `NSDraggingSession`.
- **Draw every non-empty surface as its own ring.** `Catalog.surfaces(for:)` feeds
  `WheelView.surfaces`; the modifier only sets `emphasis`. Do not reintroduce a single-surface
  `choices` assignment — `WheelView.choices` is a read-only view of the emphasized ring.
- **Wedge arcs run the short way:** outer arc `a0 → a1` counter-clockwise, inner arc `a1 → a0`
  clockwise. Invert either flag and the wheel fills as a black disc again.
- The `Wheel` log line must keep `mode`, `count`, `anchor`, `screen`, `choices` and must include
  `radius` and `outer`; the drag harness aims at `radius` for the emphasized ring and uses
  `outer + 14` for the anchor clamp. `rings=mode:count,…` is diagnostic.
- Ring labels must fit the wedge chord: `2 · midRadius · sin(step/2) − 12` at the drawn font.
  `uitest` asserts this for every kind; do not shrink the radius or raise the font without
  re-running it.
- PDF compression must pass a per-page `kCGPDFContextMediaBox`; do not regress to one default box.
- PDF image extraction must keep native XObject pixels; use the page render only when a page has no
  image XObject.
- OCR is fallback-only: use PDFKit text when it exists, Vision only when it is empty.
- `selftest` currently reports 83 checks and `uitest` reports 25; add a check whenever a converter,
  engine option, or UI path is added, and keep the structural verifiers.

## Feature surface

- Menu-bar-only, drag files in Finder, tap a modifier to arm a wheel:
  **Shift = formats**, **Command = tools**, **Control = actions**.
- Format surface: images JPG/PNG/WebP/HEIC/TIFF/AVIF/BMP + PDF; video MP4/MOV/MKV/WebM/AVI/WMV/
  GIF; audio MP3/M4A/WAV/FLAC/OGG/Opus/AIFF/WMA; PDF→DOCX/PAGES/PPTX/XLSX/JPG/PNG/EPUB/TXT/MD;
  documents; spreadsheets; subtitles; archives ZIP/TAR/GZIP (RAR input only).
- Actions: AirDrop, Float, Copy, Move, Copy Path, Terminal, Reveal.
- Tools: compress/exact size, resize, crop, rotate, flip, adjust, grayscale, annotate, redact,
  strip metadata, collage, QR, trim, split, join, speed, snapshot, GIF, mute, extract audio,
  normalize, bleep, channels, sample rate, PDF merge/split/reorder/rotate/extract images.

## Coverage checklist

Legend: `[x]` = verified headlessly; `[~]` = automated in-process smoke (`uitest`) or launch,
but not a full physical interaction; `[ ]` = still needs a real interaction or manual run. Do not
promote a `[~]` row to `[x]` without the real drag or manual test.

- [~] Menu-bar app, no Dock icon, status item, Settings, demo wheel (status menu and Settings
  construction verified; demo wheel manual)
- [~] Permission-free drag watcher, three-ring wheel, drop-to-commit (external harness drives real
  Finder drags through Shift/Command/Control; mid-drag trigger switching still manual). The wheel
  shows formats, tools, and actions at once; the trigger brightens its ring.
- [x] Image conversions (9 + PDF), WebP via cwebp, image tools — headless
- [x] Video/audio conversions + media tools — headless
- [x] PDF conversions and page operations — headless; OCR, embedded extraction, mixed page sizes
- [x] Documents: PDF/DOCX/TXT/MD/RTF/HTML/EPUB — headless
- [x] Spreadsheets: CSV/TSV/XLSX/ODS (PDF render) — headless
- [x] Subtitles: SRT/VTT/TXT + shift/merge — headless
- [x] Archives: ZIP/TAR/GZIP create/extract/convert — headless
- [~] Actions: Copy Path and Float row close verified by the harness; AirDrop, Float drag-out,
  Copy, Move, Terminal, Reveal manual
- [~] HUD progress, reveal-on-click (keepBoth/replace and the drag HUD verified; reveal-on-click
  manual)
- [x] `selftest` green (83)
- [x] `uitest` green (25)
- [~] External drag harness: 12 scenarios; two consecutive full runs on the three-ring wheel
  passed 12/12 (2026-10-23)
- [~] Float panel: rows, per-row close, and panel close verified live; drag-out and double-click
  manual
- [~] Tool editors: crop, annotate, redact, metadata verified by the external harness
- [~] Finder Services: handler opens the wheel and LaunchServices lists `Convert with Zest`
  (`public.item` → `convertWithZest`); invoking it from the Finder menu is manual
- [ ] Keyboard control (Accessibility): arrows/Return/Escape (requires Zest TCC grant)
- [ ] Enter-on-selected-file in Finder (AX available; AXObserver not implemented)
- [ ] Pages output (requires `/Applications/Pages.app`; absent here)
- [ ] LibreOffice slides/legacy Office output (requires `soffice`; absent here)

## Style

Swift 5 language mode, AppKit programmatic UI, no storyboards, no third-party packages. Keep
shipped paths complete: unsupported operations must fail with a clear message and be hidden from
the wheel when the engine is absent. Update this file in the same session as any architecture
change.
