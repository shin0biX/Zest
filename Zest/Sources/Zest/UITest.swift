import AppKit
import PDFKit

// MARK: - UI smoke suite
//
// Exercises the wheel, overlay, drag watcher, planner, HUD, Float panel,
// Settings window and Services entry point without Accessibility or synthetic
// events. The physical Finder drag is still covered by the operator checklist;
// this suite proves the code those events land on.

enum UITest {
    static func run() -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Prefs.register()
        let root = Temp.dir(prefix: "zest-uitest")
        print("Zest uitest — \(root.path)")

        RecentStore.clear()
        var harness = Harness()
        do {
            let png = root.appendingPathComponent("photo.png")
            let png2 = root.appendingPathComponent("second.png")
            try makePNG(png, color: .systemOrange)
            try makePNG(png2, color: .systemTeal)
            runSuite(root: root, png: png, png2: png2, harness: &harness)
        } catch {
            harness.fail += 1
            print("FAIL  setup: \(error.localizedDescription)")
        }

        print("")
        print("\(harness.pass) passed · \(harness.fail) failed")
        if harness.fail > 0 {
            print("Log: \(Log.url.path)")
            return 1
        }
        print("All UI checks passed.")
        return 0
    }

    // MARK: Suite

    private static func runSuite(root: URL, png: URL, png2: URL,
                                 harness: inout Harness) {
        harness.check("Catalog: every kind and mode has choices") {
            for kind in sampleKinds {
                let url = try sampleURL(kind, root: root)
                for mode in [WheelMode.convert, .tools, .actions] {
                    let choices = Catalog.choices(for: [url], mode: mode)
                    try expect(!choices.isEmpty, "\(kind.rawValue) \(mode.rawValue) wheel is empty")
                }
            }
        }

        harness.check("Catalog: source format is not offered") {
            let pngChoices = Catalog.choices(for: [png], mode: .convert)
            try expect(!pngChoices.contains { $0.id == "fmt-png" }, "PNG is offered as a PNG output")
            let pdf = root.appendingPathComponent("source.pdf")
            try TextTools.pdf(from: "sample", to: pdf)
            let pdfChoices = Catalog.choices(for: [pdf], mode: .convert)
            try expect(!pdfChoices.contains { $0.id == "fmt-pdf" }, "PDF is offered as a PDF output")
        }

        harness.check("Catalog: tool ids are unique per kind") {
            for kind in sampleKinds {
                let ids = Catalog.tools(for: kind).map(\.id)
                try expect(Set(ids).count == ids.count, "duplicate tools for \(kind.rawValue)")
            }
        }

        harness.check("Catalog: surfaces never repeat a choice") {
            for kind in sampleKinds {
                let url = try sampleURL(kind, root: root)
                let surfaces = Catalog.surfaces(for: [url])
                try expect(!surfaces.isEmpty, "\(kind.rawValue) has no wheel surfaces")
                let ids = surfaces.flatMap { $0.choices.map(\.id) }
                try expect(Set(ids).count == ids.count,
                           "\(kind.rawValue) repeats a choice across rings: \(ids)")
            }
        }

        harness.check("Wheel: every slice in every ring hit-tests to its choice") {
            let wheel = makeWheel(png, mode: .convert)
            let modes = wheel.rings.map(\.mode)
            try expect(modes == [.convert, .tools, .actions],
                       "image wheel rings are \(modes.map(\.rawValue)), expected formats/tools/actions")
            for (ringIndex, ring) in wheel.rings.enumerated() {
                try expect(!ring.choices.isEmpty, "ring \(ring.mode.rawValue) is empty")
                for (index, choice) in ring.choices.enumerated() {
                    let hit = wheel.choice(at: slicePoint(wheel, ring: ring, index: index))
                    try expect(hit?.id == choice.id,
                               "ring \(ringIndex) slice \(index) hit \(hit?.id ?? "nil"), "
                               + "expected \(choice.id)")
                }
            }
        }

        harness.check("Wheel: fan style shows one surface and switches") {
            let wheel = makeWheel(png, mode: .convert)
            wheel.style = .fan
            try expect(wheel.rings.count == 1, "fan drew \(wheel.rings.count) rings")
            try expect(wheel.rings.first?.mode == .convert, "fan did not start on formats")
            wheel.emphasize(.tools)
            try expect(wheel.rings.first?.mode == .tools,
                       "fan did not rebuild for tools")
            guard let ring = wheel.rings.first else { throw ZestError("fan ring missing") }
            for (index, choice) in ring.choices.enumerated() {
                let hit = wheel.choice(at: slicePoint(wheel, ring: ring, index: index))
                try expect(hit?.id == choice.id,
                           "fan slice \(index) hit \(hit?.id ?? "nil"), expected \(choice.id)")
            }
            wheel.emphasize(.actions)
            try expect(wheel.rings.first?.mode == .actions,
                       "fan did not rebuild for actions")
            wheel.style = .rings
            try expect(wheel.rings.count == 3, "switching back to rings kept \(wheel.rings.count) rings")
        }

        harness.check("Wheel: fan petals keep a gap at every seam") {
            let wheel = makeWheel(png, mode: .tools)
            wheel.style = .fan
            guard let ring = wheel.rings.first else { throw ZestError("fan ring missing") }
            guard ring.choices.count == wheel.fanPetals.count, !wheel.fanPetals.isEmpty else {
                throw ZestError("fan petals did not build")
            }
            let petals = wheel.fanPetals
            // Walk every adjacent pair, including the wrap boundary, and
            // sample the shared seam through the whole body. The seam point
            // must sit in neither petal, and the model width profile — the
            // same cubic the path is built from — must leave a visible gap.
            for index in petals.indices {
                let neighbour = (index + 1) % petals.count
                let seam = ring.startAngle - (CGFloat(index) + 1) * ring.step
                let petal = petals[index]
                for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let radius = petal.sideInner + petal.length * fraction
                    let point = NSPoint(x: wheel.center.x + cos(seam) * radius,
                                        y: wheel.center.y + sin(seam) * radius)
                    try expect(!petal.path.contains(point)
                                   && !petals[neighbour].path.contains(point),
                               "petals \(index)/\(neighbour) cover the seam "
                               + "at \(Int(radius))pt")
                    let pitchHalf = radius * sin(ring.step / 2)
                    let half = FanPetalGeometry.halfWidth(
                        at: fraction, inner: petal.innerHalf, outer: petal.outerHalf)
                    let gap = 2 * (pitchHalf - half)
                    try expect(gap >= 4.5,
                               "gap between petals \(index)/\(neighbour) pinches to "
                               + "\(String(format: "%.1f", gap))pt at \(Int(radius))pt")
                }
            }
        }

        harness.check("Wheel: every fan label fits its petal") {
            for kind in sampleKinds {
                let url = try sampleURL(kind, root: root)
                let wheel = makeWheel(url, mode: .convert)
                wheel.style = .fan
                guard let ring = wheel.rings.first else { throw ZestError("fan ring missing") }
                guard ring.choices.count == wheel.fanPetals.count, !wheel.fanPetals.isEmpty else {
                    throw ZestError("fan petals missing for \(kind.rawValue)")
                }
                let isFormat = ring.choices.contains { choice in
                    if case .format = choice.payload { return true } else { return false }
                }
                let scale = max(0.70, wheel.fanScale)
                let font = isFormat
                    ? WheelView.fanFormatFont(for: ring.choices,
                                              available: wheel.fanPetals[0].labelWidth,
                                              scale: scale)
                    : WheelView.fanLabelFont(for: ring.choices,
                                             available: wheel.fanPetals[0].labelWidth,
                                             scale: scale)
                for (index, petal) in wheel.fanPetals.enumerated() {
                    let choice = ring.choices[index]
                    let width = (choice.title as NSString)
                        .size(withAttributes: [.font: font]).width
                    try expect(width <= petal.labelWidth + 0.5,
                               "\(kind.rawValue)/\(ring.mode.rawValue): \(choice.title) "
                               + "needs \(Int(width))pt, petal gives "
                               + "\(Int(petal.labelWidth))pt")
                }
            }
        }

        harness.check("Wheel: hub and outside cancel") {
            let wheel = makeWheel(png, mode: .convert)
            try expect(wheel.choice(at: wheel.center) == nil, "hub returned a choice")
            let outside = NSPoint(x: wheel.center.x + wheel.outerRadius + 8, y: wheel.center.y)
            try expect(wheel.choice(at: outside) == nil, "outside returned a choice")
        }

        harness.check("Wheel: every label fits its wedge") {
            for kind in sampleKinds {
                let url = try sampleURL(kind, root: root)
                let wheel = makeWheel(url, mode: .convert)
                for ring in wheel.rings {
                    let available = max(46, 2 * ring.mid * sin(ring.step / 2) - 12)
                    for choice in ring.choices {
                        let font = WheelView.labelFont(for: choice, in: ring)
                        let width = (choice.title as NSString)
                            .size(withAttributes: [.font: font]).width
                        try expect(width <= available + 0.5,
                                   "\(kind.rawValue)/\(ring.mode.rawValue): "
                                   + "\(choice.title) needs \(Int(width))pt, wedge gives "
                                   + "\(Int(available))pt")
                    }
                }
            }
        }

        harness.check("Wheel: hover follows slices and clears in the hub") {
            let wheel = makeWheel(png, mode: .convert)
            let oldSound = Prefs.playSound
            Prefs.playSound = false
            defer { Prefs.playSound = oldSound }
            let tools = try ring(.tools, in: wheel)
            wheel.hover(at: slicePoint(wheel, ring: tools, index: 2))
            try expect(wheel.hovered == WheelHit(ring: 1, index: 2),
                       "hover did not select tool slice 2")
            try expect(wheel.hoveredChoice?.id == tools.choices[2].id,
                       "hovered choice is \(wheel.hoveredChoice?.id ?? "nil")")
            wheel.hover(at: wheel.center)
            try expect(wheel.hovered == nil, "hub did not clear hover")
        }

        harness.check("Wheel: a drop commits the slice under the pointer") {
            let wheel = makeWheel(png, mode: .convert)
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 800),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = wheel
            defer { window.close() }
            var picked: WheelChoice?
            var pickedMode: WheelMode?
            wheel.onPick = { picked = $0; pickedMode = $1 }
            let tools = try ring(.tools, in: wheel)
            let point = slicePoint(wheel, ring: tools, index: 3)
            let info = FakeDragInfo(location: point, window: window)
            try expect(wheel.performDragOperation(info), "drop was not accepted")
            try expect(picked?.id == tools.choices[3].id,
                       "drop picked \(picked?.id ?? "nil"), expected \(tools.choices[3].id)")
            try expect(pickedMode == .tools,
                       "drop reported mode \(pickedMode?.rawValue ?? "nil"), expected tools")
        }

        harness.check("Overlay: opens at the anchor, switches emphasis, keeps every ring") {
            let previousStyle = Prefs.wheelStyle
            Prefs.wheelStyle = .rings
            defer { Prefs.wheelStyle = previousStyle }
            let overlay = OverlayController()
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let anchor = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
            overlay.arm(context: DragContext(urls: [png], anchor: anchor, kind: .image),
                        mode: .convert)
            pump(0.05)
            defer { overlay.close() }
            try expect(overlay.isOpen, "overlay did not open")
            let panel = try overlayWindow()
            try expect(panel.contentView is WheelView, "overlay content is not a wheel")
            let wheel = panel.contentView as! WheelView
            let expected = NSPoint(x: anchor.x - screen.frame.minX, y: anchor.y - screen.frame.minY)
            try expect(abs(wheel.center.x - expected.x) < 1 && abs(wheel.center.y - expected.y) < 1,
                       "wheel center \(wheel.center) did not match anchor \(expected)")
            let before = wheel.center
            let rings = wheel.rings.map(\.mode)
            try expect(rings == [.convert, .tools, .actions],
                       "image wheel rings are \(rings.map(\.rawValue))")
            overlay.setMode(.tools)
            pump(0.03)
            try expect(wheel.emphasis == .tools, "Command did not emphasize the tools ring")
            try expect(wheel.rings.map(\.mode) == [.convert, .tools, .actions],
                       "switching emphasis hid a ring")
            try expect(wheel.center == before, "mode switch moved the wheel")
            try expect(wheel.ring(for: .convert)?.choices.contains { $0.id == "fmt-jpg" } == true,
                       "the formats ring disappeared when tools were armed")
            overlay.setMode(.actions)
            pump(0.03)
            try expect(wheel.emphasis == .actions, "Control did not emphasize the actions ring")
        }

        harness.check("Overlay: Escape closes") {
            let overlay = OverlayController()
            overlay.arm(context: DragContext(urls: [png], anchor: .zero, kind: .image),
                        mode: .actions)
            pump(0.03)
            try expect(overlay.handleKey(53), "Escape was not consumed")
            pump(0.03)
            try expect(!overlay.isOpen, "overlay stayed open")
        }

        harness.check("Overlay: arrows step across rings and Return commits") {
            let overlay = OverlayController()
            var committed: String?
            var committedMode: WheelMode?
            overlay.onCommit = { _, choice, mode in
                committed = choice.id
                committedMode = mode
            }
            overlay.arm(context: DragContext(urls: [png], anchor: .zero, kind: .image),
                        mode: .actions)
            pump(0.03)
            try expect(overlay.handleKey(123), "left arrow was not consumed")
            let wheel = (try overlayWindow()).contentView as! WheelView
            let actions = try ring(.actions, in: wheel)
            guard let expected = actions.choices.last else {
                throw ZestError("the actions ring is empty")
            }
            try expect(wheel.hoveredChoice?.id == expected.id,
                       "left arrow selected \(wheel.hoveredChoice?.id ?? "nil"), "
                       + "expected the last action \(expected.id)")
            try expect(overlay.handleKey(36), "Return was not consumed")
            pump(0.03)
            try expect(committed == expected.id, "Return committed \(committed ?? "nil")")
            try expect(committedMode == .actions, "commit lost the ring mode")
            try expect(!overlay.isOpen, "overlay stayed open after commit")
        }

        harness.check("DragWatcher: arms with Shift and disarms on release") {
            let watcher = DragWatcher()
            var armed: (DragContext, WheelMode)?
            var disarmed = false
            watcher.onArm = { armed = ($0, $1) }
            watcher.onDisarm = { disarmed = true }
            let board = NSPasteboard(name: .drag)
            let before = board.changeCount
            watcher.process(flags: [.shift], pressed: true, change: before)
            try expect(armed == nil, "armed before the drag pasteboard changed")
            board.clearContents()
            board.writeObjects([png as NSURL])
            let after = board.changeCount
            watcher.process(flags: [.shift], pressed: true, change: after)
            try expect(armed?.0.urls.first?.lastPathComponent == png.lastPathComponent,
                       "drag context lost the file URL")
            try expect(armed?.1 == .convert, "Shift did not arm formats")
            watcher.process(flags: [], pressed: false, change: after)
            try expect(!disarmed, "disarmed before the drop could arrive")
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            try expect(disarmed, "release did not disarm after the grace period")
        }

        harness.check("DragWatcher: a new drag cancels a pending disarm") {
            let watcher = DragWatcher()
            var armed = 0
            var disarmed = 0
            watcher.onArm = { _, _ in armed += 1 }
            watcher.onDisarm = { disarmed += 1 }
            let board = NSPasteboard(name: .drag)
            board.clearContents()
            board.writeObjects([png as NSURL])
            let first = board.changeCount
            watcher.process(flags: [.shift], pressed: true, change: first)
            try expect(armed == 1, "first drag did not arm")
            watcher.process(flags: [.shift], pressed: false, change: first)
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
            board.clearContents()
            board.writeObjects([png2 as NSURL])
            let second = board.changeCount
            watcher.process(flags: [.shift], pressed: true, change: second)
            try expect(armed == 2, "second drag did not arm")
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            try expect(disarmed == 0, "a pending disarm fired over a new drag")
            watcher.process(flags: [], pressed: false, change: second)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            try expect(disarmed == 1, "second release did not disarm")
        }

        harness.check("DragWatcher: Command then Control switch modes") {
            let watcher = DragWatcher()
            var mode: WheelMode?
            var seen: [WheelMode] = []
            watcher.onArm = { _, m in mode = m; seen.append(m) }
            watcher.onSwitch = { m in mode = m; seen.append(m) }
            let board = NSPasteboard(name: .drag)
            board.clearContents()
            board.writeObjects([png as NSURL])
            let change = board.changeCount
            watcher.process(flags: [.command], pressed: true, change: change)
            try expect(mode == .tools, "Command did not arm tools")
            watcher.process(flags: [.command, .control], pressed: true, change: change)
            try expect(mode == .actions, "Control did not switch to actions")
            watcher.process(flags: [.command, .control, .shift], pressed: true, change: change)
            try expect(mode == .convert, "Shift did not switch back to formats")
            try expect(seen == [.tools, .actions, .convert],
                       "unexpected mode sequence \(seen.map(\.rawValue))")
            watcher.process(flags: [], pressed: false, change: change)
        }

        harness.check("Planner: image converts beside the source") {
            let before = Set((try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil))?
                .map { $0.resolvingSymlinksInPath().path } ?? [])
            let fmt = try format("jpg", for: .image)
            Planner.submit(context: DragContext(urls: [png], anchor: .zero, kind: .image),
                           choice: choice(for: fmt), mode: .convert)
            let out = root.appendingPathComponent("photo.jpg")
            try expect(wait(30) { FileManager.default.fileExists(atPath: out.path) },
                       "no JPG appeared")
            try expect(try ImageEngine.load(out).width > 0, "JPG is unreadable")
            let after = Set((try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil))?
                .map { $0.resolvingSymlinksInPath().path } ?? [])
            try expect(after.subtracting(before).contains(out.resolvingSymlinksInPath().path),
                       "unexpected output path; new files: \(after.subtracting(before))")
            HUDController.shared.dismiss()
        }

        harness.check("Planner: two images become one PDF") {
            let pdfsBefore = try pdfs(in: root)
            let fmt = try format("pdf", for: .image)
            Planner.submit(context: DragContext(urls: [png, png2], anchor: .zero, kind: .image),
                           choice: choice(for: fmt), mode: .convert)
            var created: URL?
            _ = wait(30) {
                let now = (try? pdfs(in: root)) ?? []
                created = now.subtracting(pdfsBefore).first
                return created != nil
            }
            guard let created else { throw ZestError("no combined PDF appeared") }
            guard let doc = PDFDocument(url: created) else {
                throw ZestError("combined PDF is unreadable")
            }
            try expect(doc.pageCount == 2, "combined PDF has \(doc.pageCount) pages, expected 2")
            HUDController.shared.dismiss()
        }

        harness.check("Planner: folder becomes a ZIP beside it") {
            let folder = root.appendingPathComponent("bundle", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "one".write(to: folder.appendingPathComponent("one.txt"), atomically: true,
                            encoding: .utf8)
            try "two".write(to: folder.appendingPathComponent("two.txt"), atomically: true,
                            encoding: .utf8)
            let fmt = try format("zip", for: .folder)
            Planner.submit(context: DragContext(urls: [folder], anchor: .zero, kind: .folder),
                           choice: choice(for: fmt), mode: .convert)
            let out = root.appendingPathComponent("bundle.zip")
            try expect(wait(30) { FileManager.default.fileExists(atPath: out.path) },
                       "no ZIP appeared")
            let listing = try Shell.run("/usr/bin/unzip", ["-l", out.path])
            try expect(listing.contains("one.txt") && listing.contains("two.txt"),
                       "ZIP is missing the folder contents")
            HUDController.shared.dismiss()
        }

        harness.check("Naming: keepBoth renames, replace reuses the path") {
            let old = Prefs.collisionPolicy
            defer { Prefs.collisionPolicy = old }
            let base = root.appendingPathComponent("collision.png")
            try "x".write(to: base, atomically: true, encoding: .utf8)
            Prefs.collisionPolicy = "keepBoth"
            let kept = Naming.output(for: png, ext: "png")
            try expect(kept.lastPathComponent == "photo 2.png",
                       "keepBoth produced \(kept.lastPathComponent)")
            Prefs.collisionPolicy = "replace"
            let replaced = Naming.output(for: png, ext: "png")
            try expect(replaced.lastPathComponent == "photo.png",
                       "replace produced \(replaced.lastPathComponent)")
        }

        harness.check("HUD: one panel, success, failure, dismiss") {
            HUDController.shared.dismiss()
            let token = HUDController.shared.begin("Alpha")
            pump(0.08)
            guard let panel = hudPanel() else { throw ZestError("HUD panel did not appear") }
            try expect(findTexts(in: panel.contentView ?? NSView()).contains("Alpha"),
                       "HUD lost the job title")
            HUDController.shared.succeed(token, outputs: [png])
            pump(0.03)
            try expect(findTexts(in: panel.contentView ?? NSView()).contains {
                $0.hasPrefix("Done ·")
            }, "HUD did not show success")
            let second = HUDController.shared.begin("Beta")
            HUDController.shared.fail(second, message: "synthetic failure")
            pump(0.03)
            try expect(hudPanel() === panel, "HUD spawned a second panel")
            try expect(findTexts(in: panel.contentView ?? NSView()).contains("synthetic failure"),
                       "HUD did not show the failure")
            HUDController.shared.dismiss()
            pump(0.03)
            try expect(hudPanel() == nil, "HUD did not dismiss")
        }

        harness.check("Float: panel lists both rows") {
            FloatingFiles.show([png, png2])
            pump(0.25)
            let panels = NSApp.windows.filter { abs($0.frame.width - 304) < 1 }
            guard let panel = panels.last else { throw ZestError("Float panel did not appear") }
            let texts = findTexts(in: panel.contentView ?? NSView())
            try expect(texts.contains("Floating · 2 files"), "Float header is wrong: \(texts)")
            try expect(texts.contains(png.lastPathComponent) && texts.contains(png2.lastPathComponent),
                       "Float rows are missing files: \(texts)")
            panel.close()
        }

        harness.check("Settings: Quick Convert favorites persist and resolve") {
            let previous = Prefs.favoriteOutput(for: .image)
            defer { Prefs.setFavoriteOutput(previous, for: .image) }
            Prefs.setFavoriteOutput("jpg", for: .image)
            try expect(Prefs.favoriteOutput(for: .image) == "jpg",
                       "favorite did not persist")
            Prefs.setFavoriteOutput(nil, for: .image)
            try expect(Prefs.favoriteOutput(for: .image) == nil,
                       "clearing the favorite did not persist")
            // The Quick Convert path resolves the same choice id the wheel uses.
            Prefs.setFavoriteOutput("jpg", for: .image)
            let resolved = Catalog.choices(for: [png], mode: .convert)
                .first { $0.id == "fmt-jpg" }
            try expect(resolved != nil, "favorite choice did not resolve from the catalog")
        }

        harness.check("Planner: conversions are recorded for Run again") {
            let entries = RecentStore.load()
            try expect(!entries.isEmpty, "no recent entries after planner runs")
            guard let entry = entries.first else { throw ZestError("no entry") }
            try expect(entry.choiceId.hasPrefix("fmt-"), "unexpected entry \(entry.choiceId)")
            let inputs = entry.inputPathsWithExistenceCheck()
            try expect(!inputs.isEmpty, "entry inputs no longer exist")
            try expect(RecentStore.choice(for: entry, inputs: inputs) != nil,
                       "recorded choice no longer resolves from the catalog")
            RecentStore.clear()
        }

        harness.check("Settings: window builds and reflects prefs") {
            let old = Prefs.collisionPolicy
            defer { Prefs.collisionPolicy = old }
            Prefs.collisionPolicy = "keepBoth"
            let window = SettingsWindow()
            guard let content = window.window?.contentView else {
                throw ZestError("Settings window has no content")
            }
            let popups = findPopups(in: content)
            guard let collision = popups.first(where: { $0.itemTitles == ["Keep both", "Replace"] })
            else { throw ZestError("collision popup missing") }
            try expect(collision.indexOfSelectedItem == 0, "collision popup ignored keepBoth")
            window.window?.close()

            Prefs.collisionPolicy = "replace"
            let second = SettingsWindow()
            let secondContent = second.window?.contentView ?? NSView()
            let secondPopups = findPopups(in: secondContent)
            guard let secondCollision = secondPopups.first(where: {
                $0.itemTitles == ["Keep both", "Replace"]
            }) else { throw ZestError("second collision popup missing") }
            try expect(secondCollision.indexOfSelectedItem == 1, "collision popup ignored replace")
            second.window?.close()
        }

        harness.check("Settings: every tab and format page builds") {
            let window = SettingsWindow()
            window.exerciseForTesting()
            guard let content = window.window?.contentView else {
                throw ZestError("settings content disappeared")
            }
            try expect(!content.subviews.isEmpty, "settings content is empty")
            window.window?.close()
        }

        harness.check("Services: Convert with Zest opens the wheel") {
            let delegate = AppDelegate()
            let board = NSPasteboard.withUniqueName()
            board.clearContents()
            board.writeObjects([png as NSURL])
            var error: NSString = ""
            delegate.convertWithZest(board, userData: "", error: &error)
            pump(0.08)
            defer { delegate.overlay.close() }
            guard let panel = try? overlayWindow() else {
                throw ZestError("services did not open the overlay")
            }
            let wheel = panel.contentView as! WheelView
            try expect(wheel.count == 1, "services passed \(wheel.count) files, expected 1")
            try expect(wheel.kind == .image, "services detected \(wheel.kind?.rawValue ?? "nil")")
        }

        harness.check("Status item: menu is wired") {
            // Keep the first-run Welcome from presenting while the suite
            // drives a real app delegate.
            let seenBefore = Prefs.welcomeSeen
            Prefs.welcomeSeen = true
            defer { Prefs.welcomeSeen = seenBefore }
            let delegate = AppDelegate()
            delegate.applicationDidFinishLaunching(
                Notification(name: NSApplication.didFinishLaunchingNotification))
            defer {
                delegate.applicationWillTerminate(
                    Notification(name: NSApplication.willTerminateNotification))
            }
            let mirror = Mirror(reflecting: delegate)
            guard let item = mirror.descendant("statusItem") as? NSStatusItem else {
                throw ZestError("status item was not created")
            }
            defer { NSStatusBar.system.removeStatusItem(item) }
            try expect(item.button?.image != nil, "status item has no icon")
            let titles = item.menu?.items.map(\.title) ?? []
            try expect(titles.contains("Convert Files…"), "menu is missing Convert Files")
            try expect(!titles.contains("Preview Wheel"), "menu still shows Preview Wheel")
            try expect(!titles.contains("Getting Started…"), "menu still shows Getting Started")
            try expect(titles.contains("Settings…"), "menu is missing Settings")
            try expect(titles.contains("Quit Zest"), "menu is missing Quit")
        }

        harness.check("Actions: Copy Path writes the clipboard") {
            let board = NSPasteboard.general
            let old = board.string(forType: .string)
            defer {
                board.clearContents()
                if let old { board.setString(old, forType: .string) }
            }
            Actions.perform(urls: [png], action: "copyPath")
            try expect(board.string(forType: .string) == png.path,
                       "clipboard does not hold the path")
            HUDController.shared.dismiss()
        }
    }

    // MARK: Fixtures

    private static let sampleKinds: [Kind] = [
        .image, .video, .audio, .pdf, .document, .slides, .sheet,
        .subtitle, .archive, .folder, .other
    ]

    private static func sampleURL(_ kind: Kind, root: URL) throws -> URL {
        switch kind {
        case .folder:
            let url = root.appendingPathComponent("sample-folder", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        case .image: return root.appendingPathComponent("sample.heic")
        case .video: return root.appendingPathComponent("sample.mp4")
        case .audio: return root.appendingPathComponent("sample.mp3")
        case .pdf: return root.appendingPathComponent("sample.pdf")
        case .document: return root.appendingPathComponent("sample.docx")
        case .slides: return root.appendingPathComponent("sample.pptx")
        case .sheet: return root.appendingPathComponent("sample.xlsx")
        case .subtitle: return root.appendingPathComponent("sample.srt")
        case .archive: return root.appendingPathComponent("sample.zip")
        case .other: return root.appendingPathComponent("sample.xyz")
        }
    }

    private static func makeWheel(_ url: URL, mode: WheelMode) -> WheelView {
        let wheel = WheelView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        wheel.surfaces = Catalog.surfaces(for: [url])
        wheel.emphasize(mode)
        wheel.center = NSPoint(x: 600, y: 400)
        return wheel
    }

    private static func ring(_ mode: WheelMode, in wheel: WheelView) throws -> WheelRing {
        guard let ring = wheel.ring(for: mode) else {
            throw ZestError("the \(mode.rawValue) ring is missing")
        }
        return ring
    }

    private static func slicePoint(_ wheel: WheelView, ring: WheelRing, index: Int) -> NSPoint {
        let angle = ring.midAngle(index)
        return NSPoint(x: wheel.center.x + cos(angle) * ring.mid,
                       y: wheel.center.y + sin(angle) * ring.mid)
    }

    private static func choice(for fmt: Fmt) -> WheelChoice {
        WheelChoice(id: "fmt-\(fmt.ext)", title: fmt.title, symbol: fmt.symbol,
                    hint: "", payload: .format(fmt))
    }

    private static func format(_ ext: String, for kind: Kind) throws -> Fmt {
        guard let fmt = Catalog.formats(for: kind).first(where: { $0.ext == ext }) else {
            throw ZestError("no \(ext) format for \(kind.rawValue)")
        }
        return fmt
    }

    private static func makePNG(_ url: URL, color: NSColor) throws {
        guard let image = ImageOps.canvas(width: 640, height: 420, draw: { ctx in
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 420))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: 80, y: 90, width: 220, height: 220))
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            ctx.fill(CGRect(x: 360, y: 130, width: 190, height: 190))
        }) else { throw ZestError("could not draw fixture") }
        try ImageEngine.encode(image, to: url, ext: "png", quality: 1)
    }

    private static func pdfs(in root: URL) throws -> Set<URL> {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return Set(urls.filter { $0.pathExtension.lowercased() == "pdf" })
    }

    // MARK: Window helpers

    private static func overlayWindow() throws -> NSWindow {
        guard let panel = NSApp.windows.last(where: {
            $0.isVisible && $0.level == .popUpMenu && $0.contentView is WheelView
        }) else { throw ZestError("overlay window is missing") }
        return panel
    }

    private static func hudPanel() -> NSWindow? {
        NSApp.windows.last {
            $0.isVisible && $0.level == .floating && abs($0.frame.width - 404) < 1
        }
    }

    private static func findTexts(in view: NSView) -> [String] {
        var out: [String] = []
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            out.append(field.stringValue)
        }
        if let button = view as? NSButton, !button.title.isEmpty {
            out.append(button.title)
        }
        for sub in view.subviews { out.append(contentsOf: findTexts(in: sub)) }
        return out
    }

    private static func findPopups(in view: NSView) -> [NSPopUpButton] {
        var out: [NSPopUpButton] = []
        if let popup = view as? NSPopUpButton { out.append(popup) }
        for sub in view.subviews { out.append(contentsOf: findPopups(in: sub)) }
        return out
    }

    // MARK: Timing

    @discardableResult
    private static func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private static func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
    }

    // MARK: Harness

    private struct Harness {
        var pass = 0
        var fail = 0

        mutating func check(_ label: String, _ body: () throws -> Void) {
            do {
                try body()
                pass += 1
                print("PASS  \(label)")
            } catch {
                fail += 1
                print("FAIL  \(label): \(error.localizedDescription)")
                Log.write("UITEST FAIL \(label): \(error.localizedDescription)")
            }
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw ZestError(message) }
    }
}

// MARK: - Synthetic drag info

private final class FakeDragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint
    var draggedImageLocation: NSPoint = .zero
    var draggedImage: NSImage?
    var draggingPasteboard: NSPasteboard = .general
    var draggingSource: Any?
    var draggingSequenceNumber: Int = 1
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    var springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(location: NSPoint, window: NSWindow?) {
        self.draggingLocation = location
        self.draggingDestinationWindow = window
        super.init()
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }

    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions,
                                for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}

    func resetSpringLoading() {}
}
