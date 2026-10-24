# AGENTS.md — Zest

Handoff context for any future session working in this repository.

Last verified: **2026-10-24**. Read **Current state** and **Resume checklist** before
touching code.

## What this is

**Zest** — a local-only, menu-bar file converter for macOS. Drag files in Finder, tap a
modifier, and pick a target from the wheel. This is a personal build, not a distribution.

- Repository root: `/Users/shin0bix/Downloads/targe` (git root; the app is under `Zest/`).
- Remote: <https://github.com/shin0biX/zest>. Last commit:
  `7c35f8c docs: describe the app on its own terms`.
- Working backup made before the fan wheel work:
  `/Users/shin0bix/Downloads/targe_working_2026-10-23_1310` (670 MB, includes `.git`,
  sources, builds and uncommitted changes).
- The fan wheel, the five-tab settings window, the onboarding flow, and the
  Add BG / Extract / Snapshots tools were designed for this build from layout cues only.
  No third-party code or resources were copied, and the bundled media tools from a
  reference app were tested and rejected (see *Tool resolution and packaging*).
- No network, no uploads, no telemetry, no third-party Swift packages.

## Session delta (2026-10-24, repository hygiene and wheel redesign proposal)

### Repository

- `RE/` is **not tracked**. It stays on disk at `RE/` (4.4 MB of reference evidence),
  is listed in `.gitignore`, and is not needed to build, test or run the app.
- Two commits landed on `main` and were pushed: `238089f` (fan wheel, settings,
  onboarding, app icon, media tools) and `7c35f8c` (docs: describe the app on its own
  terms).
- `6f154bf` was the original commit for that work. It carried `RE/` and named the
  reference app; it was rewritten and force-pushed. Anyone who fetched before the
  rewrite still holds it locally. GitHub keeps the dangling object addressable by SHA
  until it garbage collects.
- Source comments in `CLI.swift`, `Overlay.swift`, `Prefs.swift`, `Settings.swift` and
  `WelcomeWindow.swift` no longer name the reference app. Check with
  `git grep -in <name> -- . ':!RE'`; it must return nothing.
- `.gitignore` now covers `RE/` and `Zest/Zest 2.app/`.
- `swift build` clean after the doc and comment pass; the Swift diff was comments only,
  so the 93/27 suite results still stand.

### Wheel redesign: proposal stage, nothing built

The operator rejected the current fan as ugly. **No shipping code changed.** Decision
pending.

Findings from the shipping fan (`Zest wheel out.png --style fan --mode tools`):

- **Labels collide at 15 items.** 15 evenly divided slices give 24° each. At the label
  radius of 180 pt the chord is `2·180·sin(12°) ≈ 75 pt`, minus padding ≈ 63 pt.
  "EXACT SIZE" at 9.5 pt uppercase with tracking measures ≈ 70 pt, so it overflows into
  the neighbouring petal — visible on EXACT SIZE, RESIZE, CROP, ROTATE, FLIP, ADJUST,
  GRAYSCALE and ANNOTATE. `Overlay.swift` picks the fan font from item *count*
  (`base = count > 12 ? 9.5 : …`) and never measures the label. The ring wheel's
  `labelFont(for:in:)` does real chord fitting; the fan has no equivalent.
- **The hub is 45% of the disc.** 112 pt inner radius inside a 496 pt disc holds one
  line, "1 FILE".
- Uniform grey trapezoids read as a pie chart, the `discRadius + 34` plate margin makes
  it look like a sticker on a card, and 9.5 pt all-caps with tracking is the least
  legible option available.

Four directions were rendered and reviewed:

| | Concept | Verdict |
| --- | --- | --- |
| A | Measured sunburst: wedge width allocated from measured label width, blended 55/45 with equal spacing so short labels do not become slivers | Fixes the defect, keeps the dial, geometry-only change |
| B | Speedometer: glyphs on a hairline ring, centre becomes a detail readout | Best at rest, needs hover to read, weak on first use |
| C | Spoke ring: line art, horizontal labels, no plate | Reads as a diagram, not a control |
| D | Grid dock: 5×3 tiles plus a filename header | Most legible, no longer a wheel |

Recommendation on record: **A with B's hub** — measured wedges; the centre carries
filename / format / size on two lines instead of "1 FILE"; the armed wedge gets the
accent stroke and a lifted glyph. No new interaction model, no harness rewrite beyond
the radius constant.

The mockup renderer lives outside the repository at
`/private/var/folders/pk/twz1zd0s0l9b9_2ytf9vq80c0000gn/T/opencode/wheel-mock/`.
`wheel-mock.swift` draws the four directions, `sheet.swift` composes the contact sheet.
It is a standalone AppKit binary, never links Zest, and rebuilds in about two seconds:

```sh
cd /private/var/folders/pk/twz1zd0s0l9b9_2ytf9vq80c0000gn/T/opencode/wheel-mock
swiftc -O wheel-mock.swift -o wheel-mock && ./wheel-mock .
swiftc -O sheet.swift -o sheet && ./sheet
```

That path is a temp directory and may be swept. The table above carries enough detail to
rebuild any of the four if the sources are gone.

**Next action:** pick a direction, then rebuild the fan in `Overlay.swift`
(`fanPetalPath`, the label anchor, `drawBackdrop`, and the hub redraw), re-render with
`Zest wheel`, and add a fan label-fit check to `uitest`.

## Session delta (2026-10-23, media tools, packaging, verification)

Second pass in the same session.

### Media tools (feature set complete)

- **Redact video** (`redactVideo`): `ToolUI` grabs a frame through `videoFrame`,
  `rectEditor` returns normalized geometry, then a form takes the time range and
  `blur` / `pixelate` / `box`. `MediaEngine.redactVideo` builds a split → crop →
  `gblur` / neighbor-scale / `drawbox` → `overlay` graph, enabled only between start
  and end. Output MP4, libx264, yuv420p, CRF from the video quality preset,
  `+faststart`; the rect is converted to pixels and rounded to even width/height.
- **Redact audio** (`redactAudio`): replaces a range with a sine tone (default 1 kHz)
  or silence, keeping the track length and rhythm. Uses
  `volume=0:enable='between(t,…)'`, with the sine mixed at 0.32 only inside the range.
  Keeps the video stream (`-c:v copy`) when the source has one.
- **Audio to video** (`audioToVideo`): a still image (`-loop 1`) or a solid `lavfi`
  colour, scaled and padded to the chosen frame (1080p, 720p, square, vertical),
  H.264 + AAC, `-tune stillimage`, `-shortest`.
- `Catalog` entries on the video/audio wheels, `ToolRunner` cases, and three new
  selftest checks: a black-box pixel assertion (black inside the range, untouched
  outside it), an ffprobe-readable audio redaction, and an audio→video file with both
  streams.
- Driven end-to-end through the shipping `Zest.app` binary, not only the debug build.

### Layout preferences now applied

- `pdfLayout` (`editable` default, `flowing`): `DocEngine` uses
  `TextTools.attributedDocument` for editable output and plain text for flowing.
- `epubLayout` (`flowing` default, `fixed`): `PDFEngine.writeFixedEPUB` and
  `EpubWriter.writeFixed` emit one page image per XHTML page with
  `rendition:layout = pre-paginated`; `DocEngine` paginates through CoreText first.
- `Planner` reads both from the **source** extension (`Prefs.pdfLayout(for:)`,
  `Prefs.epubLayout(for:)`) because the controls live on the DOCX/Pages/EPUB pages.
  `Prefs.epubLayout(for:)` falls back to the EPUB page's own key, so PDF→EPUB honours
  the EPUB setting.
- Image “compression” (Balanced/Strong) is still stored but is not a separate encoder
  knob; quality/size continue to drive the image path.

### Tool resolution and packaging

- `ToolFinder.resolve` now **executes** each candidate with its version flag
  (`-version`, `--version`, `-ver`) under a 2 s timeout and caches the result. A binary
  that exists but traps is skipped instead of shadowing a working Homebrew copy.
- `build.sh` applies the same test to `/Applications/*/Contents/Resources/Tools`
  candidates, copies `Resources/Tools` when present, then deletes any bundled
  `ffmpeg` / `cwebp` that fails and removes an empty `Tools` directory.
  `ZEST_TOOLS_SRC` still overrides the search.
- Reason: the reference app's bundled `ffmpeg` and `cwebp` both exit **133 (SIGTRAP)**
  on this host. They were copied once, shadowed `/opt/homebrew/bin/ffmpeg`, and made
  every media tool fail. The current bundle ships **no** media tools and resolves
  Homebrew. Do not copy a third-party app's Tools directory.
- `Prefs.defaults` now uses `.standard` when the bundle id is `com.zest.app`, removing
  the “no suite” warning in CLI runs.

### App icon

- The bundle previously shipped **no icon**; the earlier claim in this file was wrong.
  `Zest/Resources/make-icon.swift` generates `AppIcon.icns` (the wand-and-stars glyph),
  `Info.plist` sets `CFBundleIconFile`, `build.sh` copies it, and `AppIcon.image` in
  `Support.swift` loads it with a repository-path fallback so headless renders and About
  still show the real icon.

### Verification

- `swift build`: clean.
- `selftest`: **93 passed · 0 failed · 0 skipped**.
- `uitest`: **27 passed · 0 failed**.
- `./build.sh`: release bundle rebuilt with the icon, no bundled tools, ad-hoc signed.
- External harness: **12/12** on the current bundle (compact fan, 2026-10-24), after
  the icon, tool validation, and media tools landed.
- Live Settings window: titlebar, traffic lights, orange pill tabs, corrected
  checkmarks, glass vibrancy over a colourful backdrop, and the real icon on About all
  confirmed. The offscreen-preview limitation no longer applies to the live window.
- `Zest wheel` re-rendered the video and audio tool fans after the new entries; both
  15-petal layouts fit their labels.

## Session delta (2026-10-23, wheel and settings pass — earlier)

The previous release was a three-ring wheel with a single settings panel and 25 UI
checks. This session added a single-surface wheel style while keeping the ring wheel and
the existing harness path intact.

### Wheel

- `WheelView.style` now has **`.fan`** and **`.rings`**.
- **The app defaults to the fan layout** (`Prefs.wheelStyle = .fan`). `WheelView` itself
  still defaults to `.rings`, so the headless geometry tests can exercise every ring
  without changing preferences.
- Fan geometry: hub `112`, outer `248` (a 496 pt disc at native scale), one surface
  at a time, orange hover accent, rounded petals, near-black hub showing only the file
  size / count, uppercase labels. A dark rounded plate (`discRadius + 34`, corner 34)
  sits behind the fan with a soft shadow and hairline border.
- Fan content: formats are label-only with no extension badge; tools and actions stack
  a white SF-symbol glyph and label at one shared anchor, so side petals do not push the
  icon outboard of the text. Dense tool fans drop to 9.5 pt labels.
- Ring geometry: outer `288`, hub `72` (a 576 pt disc), all three surfaces visible with
  emphasis only brightening the armed ring.
- `WheelView.fanScale` shrinks the same renderer for the welcome preview. The overlay
  uses `1.0`; welcome uses `0.50` and caps the preview at eight petals.
- `WheelView.labelFont(for:in:)` is the shared font contract for drawing and the UI
  fit test. It picks the largest ring-wide size from 11.5 down to 8.5 pt that fits the
  longest title in the wedge chord.
- `Zest wheel <out.png> --style fan|rings --mode …` renders either layout. It defaults
  to `Prefs.wheelStyle`, so it now produces the fan by default.

### Settings

- New file `Zest/Sources/Zest/Settings.swift` replaces the old single-panel
  `SettingsWindow` that lived in `App.swift`.
- Five tabs: **General, Formats, Compatibility, Folders, About**.
- The window is a compact **480×620** panel with a visible **Zest Settings** title,
  `.fullSizeContentView`, no zoom button, and centered text-only orange pill tabs.
  The selected tab is a filled orange pill; the others are plain text. There is no
  logo header, no segmented-control tab bar and no sidebar.
- General is one flat card with hairline dividers: Appearance (Glass/Solid, Fan/Rings),
  General (launch at login, sound/haptics), Drag Modifiers (conversion/tools/actions
  popups, `⇧ Shift` style), Float Behaviour, Terminal app, Name collisions, and Keyboard
  Control. Helper copy sits inside the card in 10.5 pt secondary text.
- Formats uses a split layout: a 154 pt search + grouped format list on the
  left, a vertical rule, and a flat detail pane on the right. The selected row uses an
  orange wash. Every format page builds; input-only formats explain their status.
  Per-format quality, metadata, image compression/size, audio bitrate/depth, video
  quality/height, GIF frame rate/width, and PDF/EPUB layout controls persist in
  `com.zest.app`. Restore Defaults and Restore Compression Defaults are orange links;
  the latter calls `Prefs.resetImageDefaults(_:)`.
- Compatibility: a **Format Compatibility** header followed by per-group table cards
  generated from `Catalog.formats(for:)`; gated/missing engines are omitted. Checkmarks
  are neutral gray, not green, matching the reference.
- Folders: a **Folder Access** card (no bookmarks required), useful locations with Open
  links, output behaviour, and permission notes.
- About: centered app icon, **Zest**, version, tagline, orange **Getting Started…** pill,
  Open Log / Refresh Engines links, catalog stats, live engine availability, Reset All
  Settings. **There is no unlock, free-trial or paywall UI anywhere.**
- Custom AppKit primitives keep the look consistent without third-party packages:
  `SettingsCardView`, `SettingsDividerView`, `SettingsTabButton`,
  `SettingsSegmentedControl` (orange selected segment), `SettingsCheckButton`,
  `SettingsFormatRow`, `SettingsPillButton`, and `FlippedDocumentView`.
- Appearance applies to the Settings window itself (glass `NSVisualEffectView` vs. solid
  window background). The overlay/HUD remain on their own backgrounds.
- `SettingsWindow.exerciseForTesting()` is internal and used by `Zest uitest` to build
  every tab and every format detail page in one process. This is the regression guard for
  the Auto Layout crashes fixed earlier.
- Scroll documents are `FlippedDocumentView` instances. A plain `NSView` document is not
  flipped and makes a taller page open scrolled to its bottom; the General tab opens at
  the Appearance card.
- `Zest settings-preview <tab 0-4> <out.png>` renders one tab offscreen at 2×, the
  settings equivalent of `Zest wheel`. It forces `.darkAqua` and temporarily hides the
  glass material because `NSVisualEffectView` does not cache cleanly into a bitmap.
  The titlebar and traffic lights do not appear in this render; the About icon does,
  through `AppIcon.image`'s repository fallback. Use the live window for the chrome.

### Welcome / onboarding

- New file `Zest/Sources/Zest/WelcomeWindow.swift`, singleton `WelcomeWindow.shared`.
- Five pages: orange welcome, Convert, Tools, Actions, Folder access. Pages 2–4 show a
  half-scale fan preview and the configured modifier keycap.
- Opened from the status menu (**Getting Started…**) and About → **Getting Started…**.
- **It is not auto-shown at launch.** That keeps the external Finder drag harness
  deterministic. `Prefs.welcomeSeen` is set by Finish; no launch hook reads it yet.
- Escape closes the window through `WelcomePanel.cancelOperation`.

### Preferences and conversion defaults

`Prefs.swift` now has:

- `AppearanceStyle`, `WheelStyle`, `FloatBehavior`, `TerminalChoice`,
  `QualityPreset`, `ImageSizePreset`, `VideoHeightPreset`.
- `qualityPreset`, `preserveMetadata`, `imageCompression`, `imageSize`,
  `videoQuality`, `videoHeight`, `audioBitrate`, `audioBitDepth`, `gifFPS`,
  `gifWidth`, `pdfLayout`, `epubLayout` accessors keyed by output extension.
- `conversionParams(for:)` feeds `Planner.convert` → `Convert.perform`.
- Media params wired: CRF, audio bitrate, downscale-only max height, GIF fps/width,
  PCM bit depth.
- Image metadata preservation is best-effort through ExifTool when present. The encoder
  still re-encodes pixels; ExifTool copies tags afterward. Orientation/dimension tag
  sanitising is still a follow-up.
- Float behavior wired: new Float vs. add to the active Float (re-presents the union in
  one panel), per-row close removes that URL from the tracked set.
- Terminal choice wired: Terminal / iTerm2 / Warp bundle lookup, fallback to Terminal.
- Settings-facing additions: `TriggerKey.settingsTitle` (`⇧  Shift`), `QualityPreset.higher`
  displays **Higher Quality**, and `Prefs.resetImageDefaults(_:)` resets only
  compression/image-size keys for the separate restore link.

### New tools

- **Add BG** (`frame`): `ImageOps.addBackground` / `ToolRunner` / generic form. Pads the
  photo on a coloured rounded card with optional aspect (square, 4:3, 16:9, 9:16, 3:2),
  corner radius, border and shadow. Default output PNG.
- **Extract archive** (`extract`): `Catalog.archiveTools`, archive wheel, `ToolRunner`
  → `ArchiveEngine.extract`. Returns the extracted folder.
- **Snapshots** (`snapshots`): multi-frame video export. Accepts explicit times
  (`0,1,2`) or an evenly spaced count, output PNG/JPG.
- `Catalog.toolCount` now includes the archive surface.
- "Strip Metadata" is now **Strip Tags** on every surface, so dense fans do not
  truncate the label.

## Current state

- **Wheel redesign is open.** The fan was rejected as ugly; four directions are rendered
  and awaiting a decision. No shipping code has changed for it yet. See the session delta
  at the top.
- **Debug compiles clean.** `swift build`: zero errors, zero warnings.
- **Headless suite green.** **93 passed · 0 failed · 0 skipped** in debug, including the
  three media tools and both document layout modes.
- **UI smoke suite green.** **27 passed · 0 failed** via `Zest uitest`. It includes the
  fan single-surface test and the every-tab / every-format settings construction test.
- **Release bundle is current.** `./build.sh` rebuilt `Zest.app` on 2026-10-24 with
  `AppIcon.icns` and `CFBundleIconFile`. It ships **no** `Contents/Resources/Tools`
  because no candidate passed the launch probe; the app resolves
  `/opt/homebrew/bin/ffmpeg` at runtime. It is ad-hoc signed as `com.zest.app`.
- **External drag harness: 12/12 on the current bundle.** The 2026-10-24 run covered the
  compact fan, all twelve scenarios, and the rebuilt bundle. The wheel geometry and drag
  path are unchanged by the media tools.
- **Settings UI: offscreen and live passes done.** `uitest` constructs all five tabs and
  every format page; `settings-preview` matched the design targets. The live window
  confirmed the titlebar, traffic lights, orange pills, corrected checkmarks, glass
  vibrancy, and the real About icon. The earlier checkmark and popup-width defects stay
  fixed. Appearance was returned to the operator's `solid` setting after the glass pass.
- **Media tools verified.** Redact Video, Redact Audio and Audio to Video were driven
  through the shipping bundle binary. Selftest asserts a black box inside the redaction
  range and an untouched pixel outside it; ffprobe confirms both streams for audio→video.
- **Screen Recording now works for this host** (`screencapture` succeeds), but output
  files, logs and `Zest wheel` remain the primary checks. Accessibility is available to
  the automation host.
- **App launches.** The bundle logs
  `options=616 tools=64 ffmpeg=/opt/homebrew/bin/ffmpeg`; there is no bundled ffmpeg to
  shadow it.
- **Reference material** is local only. The `RE/` folder is ignored by `.gitignore` and
  is not needed to build, test or run the app.
- **Stale debris:** `Zest/Zest 2.app` is an untracked older bundle that still contains
  binaries that trap on launch. It is ignored by `.gitignore`. Do not copy its Tools
  directory or ship that bundle.

### Verification snapshot

```sh
cd Zest
swift build                       # clean (debug)
.build/debug/Zest selftest        # 93 passed · 0 failed · 0 skipped
.build/debug/Zest uitest          # 27 passed · 0 failed
.build/debug/Zest wheel /tmp/wheel-fan.png --kind image --style fan --mode tools
.build/debug/Zest settings-preview 0 /tmp/settings-general.png   # tabs 0…4
./build.sh                        # release + Zest.app + icon + ad-hoc sign
./Harness/run.sh all              # external Finder drags, 12 scenarios
open Zest.app                     # launch + log
```

Do not mark an interaction row as fully tested without the real drag or the manual run.

## Resume checklist (in order)

0. **The active thread is the wheel redesign** — proposal stage, nothing built. Read
   *Wheel redesign: proposal stage* at the top of this file, pick a direction with the
   operator, then rebuild the fan in `Overlay.swift`. Everything below is the standing
   verification path and applies once that lands.
1. **Orient on the surfaces.** `Catalog.swift` holds the format, tool and action tables;
   `Prefs.swift` the per-format defaults; `Settings.swift` every settings page. The local
   `RE/` folder is ignored by git and not needed for any of this.
2. **Rebuild the bundle after source changes.** `./build.sh`; confirm
   `Contents/Resources/AppIcon.icns` exists, the app is ad-hoc signed, and any
   `Contents/Resources/Tools` directory that remains contains only binaries that pass
   `-version`. An absent Tools directory is normal on this host: `ToolFinder` resolves
   Homebrew.
3. **Run the external harness.** `./Harness/run.sh all` (or one scenario). It needs
   Accessibility for the host, Finder on the main display, and a rebuilt `Zest.app`.
   Artifacts and failures land under `Zest/Harness/run/<scenario>/`. If a fan-mode
   scenario fails, first confirm the log line and slice radius before changing the drag
   logic; `defaults write com.zest.app wheelStyle rings` can isolate a fan regression.
   Always restore `wheelStyle fan` if that was the intended app default.
4. **Rerun the headless suites** after every code change: `<debug>/Zest selftest` and
   `uitest`.
5. **Manual UI pass:** open Settings and every tab, confirm the compact 480×620 layout,
   orange pill tabs, searchable format sidebar, and the About page has no unlock/trial
   UI. Then open Getting Started and step through all five pages, drag a file with the
   compact fan wheel, tap the modifier mid-drag, and test the Add BG / Extract /
   Snapshots / Redact Video / Redact Audio / Audio to Video forms.
6. **Remaining manual rows:** AirDrop, Float drag-out/double-click, Finder Services menu
   invocation, and keyboard navigation.
7. **Optional feature work** — see *Remaining gaps and known limits*, especially fan
   pagination, image compression strength, app-wide glass, video redaction tracking, and
   the ExifTool orientation follow-up.
8. **Update this file** with what the harness and manual run proved.

### External drag harness

Synthetic events work because the automation host is trusted. The harness is a standalone
binary (`Zest/Harness/dragtest.swift`) built by `Harness/run.sh`; it never links Zest's
code and lives outside the shipping sources. It runs twelve scenarios:

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

Mechanics (unchanged unless noted):

- Find the Finder icon: activate Finder, read the browser window by title (AXDocument is
  often nil), ensure icon view through the `AXRadioButton` described `icon view`, then the
  `AXImage` whose `AXFilename` matches. Click with `AXPosition` + half of `AXSize`.
- For a multi-file selection, click the first icon, then send Cmd+A. Scenario folders
  contain only the inputs, so select-all is exact.
- Post mouse-down, then press the trigger, then drag. **A synthetic `.flagsChanged` sent
  mid-drag is not reliably re-targeted by the window server**; press the modifier between
  mouse-down and the first drag step. `uitest` drives mid-drag mode switching in-process.
- Parse the newest `Wheel mode=… anchor=x,y screen=WxH radius=… outer=… rings=… choices=id,id,…`
  line. In **fan** mode there is one ring and `radius` is the fan mid radius (180 at scale
  1; `outer` is 248). In **rings** mode `mode` names the emphasized ring and `radius` is
  its mid radius.
  Slice 0 is centered at the top:
  `step = 2π/count`, `start = π/2 + step/2`,
  `angle = start - (index+0.5)·step`. Convert the AppKit wheel point to CG top-left
  coordinates.
- **Pause 0.35 s after the arm line before moving to the slice.** The overlay is ordered
  front and fades in just after logging; a synthetic drag that moves immediately can
  reach the slice before AppKit sends `draggingEntered`, which looks like “the drop never
  reached the wheel”. Re-post the trigger flag down if `NSEvent.modifierFlags` lost it.
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
  after launch. The 0.35 s settle and the drop retry are test-side mitigations; inspect
  `Drag start`, `Drop enter`, `Drop perform`, and `Wheel disarm` before changing app code.
- Verify structurally (ImageIO reload, page count, archive listing, tag values,
  red-pixel count, black-pixel count). Artifacts land in `Zest/Harness/run/<scenario>/`.

### Manual interaction test (remaining)

- Launch `Zest.app`. Confirm the wand-and-stars status item, no Dock icon, no window on
  launch.
- Open **Getting Started…** from the menu; step through all five pages. Confirm the fan
  previews are readable and the keycaps match the configured modifiers.
- Open **Settings**; change every popup, toggle sound/keyboard control, reopen, confirm
  persistence. Build every Formats page (the automated test does this; verify visually).
- Open **Preview Wheel** from the status menu; hover slices in the fan, tap
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
| `App.swift` | App delegate, status item, Services provider, menu, Settings/Welcome entry points, engine status. Legacy settings class was removed. |
| `Settings.swift` | Compact 480×620 five-tab settings window: orange pill tabs, flat card rows, search/sidebar Formats, compatibility matrix, Folders, About, `exerciseForTesting` seam. |
| `WelcomeWindow.swift` | Five-page onboarding, keycaps, half-scale fan preview. |
| `Support.swift` | `Shell`, `ToolFinder` (execution-validated candidates), `AppIcon`, `Kind`, `KindDetector`, `Naming`, `Bytes`, `Temp`, `Log`, `MediaProbe`, `onMain`/`onMainSync`, `ZestError`. |
| `Prefs.swift` | Suite `com.zest.app`; trigger keys, wheel/style/float/terminal choices, per-format defaults, `conversionParams(for:)`. |
| `Catalog.swift` | Format tables, tool/action tables, per-kind wheel choices, option counts. Includes `archiveTools` and Add BG / Snapshots. |
| `DragWatcher.swift` | Permission-free drag detection: `pressedMouseButtons`, modifier transitions, `NSPasteboard(name: .drag)`. |
| `Overlay.swift` | Non-activating `OverlayPanel`, `WheelView` (fan + rings), hit-testing, rounded petals, demo/preview modes, drag destination. |
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
| `UITest.swift` | `Zest uitest`: 27-check in-process UI smoke suite; fake drag context; fan and settings coverage. |
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
  carries the ring’s mode, not the armed one.
- **Fan:** one surface at a time, rebuilt by `emphasize(_:)`. `Catalog.surfaces` still
  supplies all surfaces; the fan picks the emphasized one. `rings` contains exactly one
  ring at `fanInnerRadius … fanOuterRadius`. Switching modes keeps the wheel anchored.
- **Petal arcs:** `fanPetalPath` uses short outer/inner arcs with quadratic corner joins;
  `wedgePath` for rings must keep the outer arc counter-clockwise and the inner arc back
  clockwise. Inverting either fills the annulus and buries labels.
- Ring hit-testing picks the ring by radius, then the slice by angle. Fan hit-testing uses
  `fanInner`/`fanOuter`; do not use the outer ring’s inner radius for all rings.
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
  entry and `outer` is `248` (scaled in preview only). Keep the format stable or update
  the harness.
- `Zest wheel <out.png> [--kind …] [--style fan|rings] [--mode …] [--hover N]` renders
  the wheel offscreen at 2×. It is the deterministic visual check. Screen Recording is
  now available on this host, but do not rely on screenshots for assertions.
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

`UITest.swift` runs **27 checks** in-process and needs no TCC permissions:

- Catalog: every kind × mode has choices; the source format is not offered; tool ids are
  unique; no choice appears on two surfaces of the same wheel.
- Wheel: every slice in every ring hit-tests to its choice; **fan mode renders one ring,
  switches convert → tools → actions, and every fan slice hit-tests**; hub/outside cancel;
  every ring label fits its chord at `WheelView.labelFont(for:in:)` — **fan labels are not
  checked and currently overflow at 15 items**; hover follows rings and clears in the hub;
  a fake drop commits the tools ring and reports `.tools`.
- Overlay: opens at the anchor, switching emphasis keeps all three rings (the test forces
  `wheelStyle = .rings` for this case), Escape closes, arrows step across rings and Return
  commits with the hovered ring’s mode.
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
Welcome, the live Settings window, and menu tracking remain manual. The three new media
forms are modal and are not in `uitest`; selftest plus a shipping-bundle run cover their
engine paths, but the forms still need a visual check.

## Feature inventory

The current surface — formats, tools, actions, settings and onboarding — is listed under
*Feature surface* at the end of this file. That section is the source of truth; keep it in
step with `Catalog.swift`.

### Implementation status

| Area | State | Notes |
| --- | --- | --- |
| Fan wheel | implemented | one surface, rounded petals, orange; no pagination |
| Ring wheel | kept | available in Settings, default for the geometry tests |
| Settings tabs | implemented | General/Formats/Compatibility/Folders/About |
| Welcome | implemented | 5 pages, menu/About entry, not auto-shown |
| Per-format defaults | implemented | image/video/audio/GIF wired; PDF/EPUB layout applied |
| Add BG | implemented | `frame` tool |
| Extract archive | implemented | `extract` tool |
| Video snapshots | implemented | `snapshots` tool |
| Audio to video | implemented | `audioToVideo` tool |
| Redact video/audio | implemented | `redactVideo` / `redactAudio` tools |
| Redact image | implemented | `redact` tool |
| PDF organize | implemented | reorder/split/rotate/merge |
| Launch at login | implemented | SMAppService; ad-hoc caveat |
| Float behavior | implemented | new/add union |
| Terminal choice | implemented | Terminal/iTerm/Warp lookup |
| Glass/solid | partial | Settings window only |
| Tool bundling | implemented | execution-validated, Homebrew fallback |

## Remaining gaps and known limits

1. **The mid-drag modifier tap is not machine-verified.** The external harness presses the
   trigger between mouse-down and the first drag step because macOS does not reliably
   re-target a synthetic drag to a panel that appears mid-session. Fan and ring drops are
   now driven by real Finder drags, and `uitest` covers the mode switch logic; one manual
   drag with a real Shift/Command/Control tap is still required.
2. **The fan wheel has no pagination and its labels do not fit.** It draws every choice,
   up to 15 image tools, as a petal. At 15 slices the labels overlap their neighbours —
   see *Wheel redesign: proposal stage* above for the measurement and the four candidate
   directions. Showing a smaller set at a time is also not implemented.
3. **PDF compression still rasterizes.** Text, links, annotations, and form fields are
   lost. Per-page media boxes are preserved; compression remains image-based.
4. **Embedded image extraction has a fallback.** Only image XObjects are pulled at native
   size. Inline images, stencil masks, and pages with no image XObject render the whole
   page at the requested DPI.
5. **OCR is a fallback, not document reconstruction.** `VisionOCR` runs only when PDFKit
   returns no text. Layout, tables, columns, and images are not rebuilt.
6. **DOCX reading is plain text.** `DocxReader` extracts `<w:t>` runs; DOCX→PDF/TXT/MD
   drops styling, tables, and images. Native `DocxWriter` output is minimal.
7. **Document layouts are applied, with limits.** `pdfLayout` now selects flowing text
   versus editable rich paragraphs; “editable” still means a CoreText-rendered PDF, not a
   tagged or reflowable document. `epubLayout=fixed` produces page images with
   `pre-paginated` metadata, so the text is not selectable or reflowable. Image
   “compression” (Balanced/Strong) is stored but only quality/size affect encoding.
8. **ExifTool metadata copy is best-effort.** If ExifTool exists, tags are copied after
   re-encode. Orientation and pixel-dimension tags are not yet sanitised, so a rotated
   source could need a follow-up fix.
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
16. **`convert` has no per-conversion parameters.** Use `tool` for quality/DPI/size
    controls; format defaults come from Settings.
17. **GZIP naming depends on input shape.** A single file becomes `<name>.gz`; a folder or
    multiple inputs become `<name>.tar.gz`. Extraction handles both.
18. **The fan preview in Welcome is capped at eight petals** (half scale) for readability;
    it is not the full tool set.
19. **The external harness does not exercise the media forms.** Its 12/12 run covers the
    drag path and the existing editors, not Redact Video/Audio or Audio to Video. Add a
    media scenario or run those forms manually before marking them fully exercised.

## Engine policy

- **Images:** ImageIO native (JPEG/PNG/HEIC/AVIF/TIFF/BMP/GIF/PDF). WebP encode via
  `cwebp` (ImageIO WebP encode is false). SVG via `rsvg-convert`, falling back to
  `qlmanage -t`. Metadata copy via ExifTool when available.
- **Video/audio:** ffmpeg + ffprobe via `ToolFinder` (bundle first, then Homebrew/PATH).
  GIF palette filter, exact-size bitrate search, concat with `anullsrc` for silent clips,
  metadata key mapping, redaction through `gblur` / neighbor-scale / `drawbox` filters,
  audio→video through a still or `lavfi` colour. Format defaults supply CRF, audio
  bitrate, max height, GIF fps/width, and PCM bit depth.
- **PDF:** PDFKit/CoreGraphics; PDFKit text extraction with Vision OCR fallback; embedded
  image XObjects at native size; 300 dpi page rendering by default; per-page media boxes
  when compressing; fixed-layout EPUB from page images.
- **Documents:** `textutil` for legacy/RTF/DOCX interchange; native `DocxWriter`; CoreText
  pagination. WebKit deliberately not used.
- **Office:** native CSV/TSV/XLSX/ODS readers/writers; LibreOffice (`soffice --headless
  --convert-to`) only when installed for legacy/Apple formats. Gate options on capability.
- **Archives:** `ditto`/`zip`/`tar`/`gzip`; `.tar.gz` gunzips then untars; RAR input uses
  `unar`/`unrar`; 7z needs `7zz`/`7z`.
- **Availability on this Mac:** Homebrew ffmpeg, ffprobe and cwebp; `unar`, sips, textutil,
  qlmanage, zip, tar, gzip. The app bundle ships no tools because no candidate passed the
  launch probe. Missing: ImageMagick, pandoc, rsvg-convert, 7zz/7z, unrar, LibreOffice,
  Pages/Keynote/Numbers.

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
  Keep the explicit tab widths; 88 pt truncates “Compatibility”.
- Keep formats/tools truthful: gate on `Capability`/`ToolFinder`, hide what cannot run.
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
- **Petal arcs run the short way.** Ring `wedgePath` outer arc counter-clockwise, inner
  arc clockwise. Fan `fanPetalPath` uses quadratic corner joins; keep both paths short.
- The `Wheel` log line must keep `mode`, `count`, `anchor`, `screen`, `choices` and must
  include `radius` and `outer`; the drag harness aims at `radius` and clamps with
  `outer + 14`. Fan logs one ring with `radius=180` and `outer=248` at scale 1.
- Ring labels must fit the wedge chord: `2 · midRadius · sin(step/2) − 12` at
  `WheelView.labelFont(for:in:)`. Do not shrink the radius or raise the font without
  re-running `uitest`.
- Fan labels use their own 9.5–13 pt typography and **do not currently fit at 15 items**.
  Nothing measures them: `Overlay.swift` chooses the size from `count` alone. Any fan
  redesign must measure the rendered string against its slice and add the equivalent of
  `labelFont(for:in:)` for the fan. The fit test covers rings only; re-render
  `Zest wheel --style fan --mode tools` after changing fan title lengths.
- PDF compression must pass a per-page `kCGPDFContextMediaBox`; do not regress to one
  default box.
- PDF image extraction must keep native XObject pixels; use the page render only when a
  page has no image XObject.
- OCR is fallback-only: use PDFKit text when it exists, Vision only when it is empty.
- Video redaction converts the normalized rect to pixels once, clamps it to the frame, and
  rounds width/height down to even values for yuv420p. Keep the overlay filter's `enable`
  range aligned with the requested start/end; do not apply the box to the whole clip.
- `selftest` currently reports 93 checks and `uitest` reports 27; add a check whenever a
  converter, engine option, or UI path is added, and keep the structural verifiers.

## Feature surface

- Menu-bar-only, drag files in Finder, tap a modifier to arm a wheel:
  **Shift = formats**, **Command = tools**, **Control = actions**. The app default wheel
  is the orange **fan**; **rings** remains a Settings option.
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

## Coverage checklist

Legend: `[x]` = verified headlessly; `[~]` = automated in-process smoke (`uitest`) or
launch, but not a full physical interaction; `[ ]` = still needs a real interaction or
manual run. Do not promote a `[~]` row to `[x]` without the real drag or manual test.

- [~] Menu-bar app, no Dock icon, status item, Settings, demo wheel (status menu and
  settings construction verified; demo wheel manual)
- [~] Permission-free drag watcher, fan/ring wheel, drop-to-commit (external harness
  drives fan-mode Finder drags through Shift/Command/Control; mid-drag trigger switching
  manual)
- [~] **Fan wheel**: one surface, compact 496 pt disc, dark rounded plate, gray petals,
  label-only formats, icon + label tools/actions, near-black hub with file size, mode
  rebuild (uitest + `Zest wheel`; external harness 12/12 on this geometry). **Labels
  collide at 15 items — redesign pending, do not treat the current fan as final.**
- [~] **Settings**: compact 480×620 layout, custom orange pill tabs, flat cards,
  search/sidebar Formats, compatibility tables, Folders, centered About with **no
  unlock/free-trial UI**; all five tabs and every format page build (`uitest`), all five
  tabs have been rendered offscreen (`settings-preview`) against the design targets, and
  the live window confirms titlebar, traffic lights, corrected checkmarks,
  glass vibrancy, and the real About icon. Tab-by-tab persistence review remains manual.
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
- [x] `selftest` green (93)
- [x] `uitest` green (27)
- [~] External drag harness: 12 scenarios; 12/12 on the current bundle (2026-10-24,
  compact fan, icon, tool validation, and media tools).
- [~] Float panel: rows, per-row close, and panel close verified live; drag-out,
  double-click, and add-to-existing manual
- [~] Tool editors: crop, annotate, redact, metadata verified by the external harness;
  Add BG/Snapshots/Redact Video/Redact Audio/Audio to Video forms still need a visual
  check (the engine paths are covered by selftest and a shipping-bundle run)
- [~] **App bundle**: icon present, `CFBundleIconFile` set, ad-hoc signed, no broken tools;
  `build.sh` validates candidates and the About page loads the real icon
- [~] Finder Services: handler opens the wheel and LaunchServices lists
  `Convert with Zest` (`public.item` → `convertWithZest`); invoking it from the Finder
  menu is manual
- [ ] Keyboard control (Accessibility): arrows/Return/Escape (requires Zest TCC grant)
- [ ] Enter-on-selected-file in Finder (AX available; AXObserver not implemented)
- [ ] Pages output (requires `/Applications/Pages.app`; absent here)
- [ ] LibreOffice slides/legacy Office output (requires `soffice`; absent here)

## Style

Swift 5 language mode, AppKit programmatic UI, no storyboards, no third-party packages.
Keep shipped paths complete: unsupported operations must fail with a clear message and be
hidden from the wheel when the engine is absent. Update this file in the same session as
any architecture change.
