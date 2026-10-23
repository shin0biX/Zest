import AppKit

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let watcher = DragWatcher()
    let overlay = OverlayController()
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindow?
    private var hudDemo = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "wand.and.stars",
                                accessibilityDescription: "Zest")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Zest — drag files, then tap \(Prefs.convertKey.title)"
        }
        rebuildMenu()

        watcher.onArm = { [weak self] context, mode in
            guard let self else { return }
            if self.overlay.isOpen { self.overlay.close() }
            self.overlay.arm(context: context, mode: mode)
        }
        watcher.onSwitch = { [weak self] mode in
            self?.overlay.setMode(mode)
        }
        watcher.onDisarm = { [weak self] in
            self?.overlay.handleDisarm()
        }

        overlay.onCommit = { context, choice, mode in
            Planner.submit(context: context, choice: choice, mode: mode)
        }

        KeyTap.shared.onKey = { [weak self] code in
            self?.overlay.handleKey(code) ?? false
        }
        if Prefs.keyboardControl {
            _ = KeyTap.shared.start()
        }

        watcher.start()
        Log.write("Zest launched. options=\(Catalog.optionCount) tools=\(Catalog.toolCount) ffmpeg=\(ToolFinder.ffmpeg ?? "none")")
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        KeyTap.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Files opened via Finder / "Open With" / Services.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        showWheel(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    @objc func convertWithZest(_ pboard: NSPasteboard, userData: String,
                               error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were provided." as NSString
            return
        }
        showWheel(urls)
    }

    func showWheel(_ urls: [URL]) {
        let anchor = NSEvent.mouseLocation
        let context = DragContext(urls: urls, anchor: anchor,
                                  kind: KindDetector.commonKind(urls))
        if overlay.isOpen { overlay.close() }
        overlay.arm(context: context, mode: .convert)
    }

    // MARK: Menu

    func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Drag files · tap \(Prefs.convertKey.title) for formats",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let preview = NSMenuItem(title: "Preview Wheel", action: #selector(previewWheel), keyEquivalent: "p")
        preview.target = self
        menu.addItem(preview)

        let open = NSMenuItem(title: "Convert Files…", action: #selector(openFiles), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let stats = NSMenuItem(title: "\(Catalog.optionCount) format pairs · \(Catalog.toolCount) tools",
                               action: nil, keyEquivalent: "")
        stats.isEnabled = false
        menu.addItem(stats)

        let log = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Zest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.toolTip = "Zest — drag files, then tap \(Prefs.convertKey.title)"
    }

    @objc private func previewWheel() {
        overlay.presentDemo()
    }

    @objc private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Open Wheel"
        panel.message = "Pick files to run through the wheel"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        showWheel(panel.urls)
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}

// MARK: - Settings

final class SettingsWindow: NSWindowController {
    private var convertPopup: NSPopUpButton!
    private var toolsPopup: NSPopUpButton!
    private var actionsPopup: NSPopUpButton!
    private var collisionPopup: NSPopUpButton!
    private var qualityPopup: NSPopUpButton!
    private var soundCheck: NSButton!
    private var keyboardCheck: NSButton!
    private var engineStack: NSStackView!
    private var statsLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Zest Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        build()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10.5, weight: .bold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.font = .systemFont(ofSize: 12.5)
        label.widthAnchor.constraint(equalToConstant: 158).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 12
        return stack
    }

    private func popup(_ titles: [String], action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
        popup.widthAnchor.constraint(equalToConstant: 230).isActive = true
        return popup
    }

    private func build() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        let main = NSStackView()
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 9
        main.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        main.addArrangedSubview(heading("Wheel triggers"))
        convertPopup = popup(TriggerKey.allCases.map(\.title),
                             action: #selector(convertKeyChanged(_:)))
        main.addArrangedSubview(row("Convert formats", convertPopup))
        main.setCustomSpacing(4, after: main.arrangedSubviews.last!)
        toolsPopup = popup(TriggerKey.allCases.map(\.title),
                           action: #selector(toolsKeyChanged(_:)))
        main.addArrangedSubview(row("File tools", toolsPopup))
        main.setCustomSpacing(4, after: main.arrangedSubviews.last!)
        actionsPopup = popup(TriggerKey.allCases.map(\.title),
                             action: #selector(actionsKeyChanged(_:)))
        main.addArrangedSubview(row("File actions", actionsPopup))

        main.addArrangedSubview(spacer(6))
        main.addArrangedSubview(heading("Output"))
        collisionPopup = popup(["Keep both", "Replace"], action: #selector(collisionChanged(_:)))
        main.addArrangedSubview(row("On name clash", collisionPopup))
        qualityPopup = popup(["Light", "Balanced", "Strong", "Maximum"],
                             action: #selector(qualityChanged(_:)))
        main.addArrangedSubview(row("Compression preset", qualityPopup))
        main.addArrangedSubview(row("Feedback", soundCheckbox()))

        main.addArrangedSubview(spacer(6))
        main.addArrangedSubview(heading("Control"))
        main.addArrangedSubview(row("Keyboard in wheel", keyboardCheckbox()))
        let hint = NSTextField(wrappingLabelWithString:
            "Arrow keys, Return and Escape during a drag need Accessibility. The mouse wheel needs no permissions.")
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .secondaryLabelColor
        hint.widthAnchor.constraint(equalToConstant: 500).isActive = true
        main.addArrangedSubview(hint)

        main.addArrangedSubview(spacer(6))
        main.addArrangedSubview(heading("Engines"))
        engineStack = NSStackView()
        engineStack.orientation = .vertical
        engineStack.alignment = .leading
        engineStack.spacing = 3
        refreshEngines()
        main.addArrangedSubview(engineStack)

        let engineButtons = NSStackView(views: [
            button("Refresh", #selector(refreshEngineStatus)),
            button("Choose ffmpeg…", #selector(chooseFFmpeg)),
            button("Reset to auto", #selector(resetFFmpeg))
        ])
        engineButtons.orientation = .horizontal
        engineButtons.spacing = 8
        main.addArrangedSubview(engineButtons)

        main.addArrangedSubview(spacer(6))
        statsLabel = NSTextField(labelWithString: "")
        statsLabel.font = .systemFont(ofSize: 11)
        statsLabel.textColor = .secondaryLabelColor
        main.addArrangedSubview(statsLabel)

        let footer = NSStackView(views: [
            button("Open Log", #selector(openLog)),
            button("Reset Settings", #selector(resetSettings))
        ])
        footer.orientation = .horizontal
        footer.spacing = 8
        main.addArrangedSubview(spacer(6))
        main.addArrangedSubview(footer)

        syncControls()
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        return b
    }

    private func soundCheckbox() -> NSButton {
        let check = NSButton(checkboxWithTitle: "Play a tick when a slice highlights",
                             target: self, action: #selector(soundChanged(_:)))
        soundCheck = check
        return check
    }

    private func keyboardCheckbox() -> NSButton {
        let check = NSButton(checkboxWithTitle: "Enable Arrow / Return / Escape during drags",
                             target: self, action: #selector(keyboardChanged(_:)))
        keyboardCheck = check
        return check
    }

    private func syncControls() {
        convertPopup.selectItem(at: TriggerKey.allCases.firstIndex(of: Prefs.convertKey) ?? 0)
        toolsPopup.selectItem(at: TriggerKey.allCases.firstIndex(of: Prefs.toolsKey) ?? 1)
        actionsPopup.selectItem(at: TriggerKey.allCases.firstIndex(of: Prefs.actionsKey) ?? 2)
        collisionPopup.selectItem(at: Prefs.collisionPolicy == "replace" ? 1 : 0)
        let q = ["light", "balanced", "strong", "maximum"].firstIndex(of: Prefs.quality) ?? 1
        qualityPopup.selectItem(at: q)
        soundCheck.state = Prefs.playSound ? .on : .off
        keyboardCheck.state = Prefs.keyboardControl ? .on : .off
        statsLabel.stringValue = "\(Catalog.optionCount) format pairs · \(Catalog.toolCount) tools · \(Catalog.actions.count) actions"
    }

    @objc private func convertKeyChanged(_ sender: NSPopUpButton) {
        Prefs.convertKey = TriggerKey.allCases[sender.indexOfSelectedItem]
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }

    @objc private func toolsKeyChanged(_ sender: NSPopUpButton) {
        Prefs.toolsKey = TriggerKey.allCases[sender.indexOfSelectedItem]
    }

    @objc private func actionsKeyChanged(_ sender: NSPopUpButton) {
        Prefs.actionsKey = TriggerKey.allCases[sender.indexOfSelectedItem]
    }

    @objc private func collisionChanged(_ sender: NSPopUpButton) {
        Prefs.collisionPolicy = sender.indexOfSelectedItem == 1 ? "replace" : "keepBoth"
    }

    @objc private func qualityChanged(_ sender: NSPopUpButton) {
        Prefs.quality = ["light", "balanced", "strong", "maximum"][sender.indexOfSelectedItem]
    }

    @objc private func soundChanged(_ sender: NSButton) {
        Prefs.playSound = sender.state == .on
    }

    @objc private func keyboardChanged(_ sender: NSButton) {
        Prefs.keyboardControl = sender.state == .on
        if sender.state == .on {
            if !AXIsProcessTrusted() {
                KeyTap.requestPermission()
                Alert.show("Accessibility needed",
                           detail: "Enable Zest in System Settings → Privacy & Security → Accessibility, then toggle this again.")
                return
            }
            if !KeyTap.shared.start() {
                Alert.show("Keyboard control unavailable",
                           detail: "The event tap could not be created. Mouse control still works.")
            }
        } else {
            KeyTap.shared.stop()
        }
    }

    @objc private func refreshEngineStatus() {
        refreshEngines()
    }

    private func refreshEngines() {
        guard let engineStack else { return }
        for view in engineStack.arrangedSubviews {
            engineStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let engines: [(String, String?)] = [
            ("ffmpeg", ToolFinder.ffmpeg),
            ("ffprobe", ToolFinder.ffprobe),
            ("cwebp", ToolFinder.cwebp),
            ("pandoc", ToolFinder.pandoc),
            ("LibreOffice", ToolFinder.soffice),
            ("ExifTool", ToolFinder.exiftool)
        ]
        for (name, path) in engines {
            let found = path != nil
            let label = NSTextField(labelWithString:
                "\(found ? "●" : "○")  \(name)  \(path ?? "not found")")
            label.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            label.textColor = found ? .secondaryLabelColor : .tertiaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            engineStack.addArrangedSubview(label)
        }
        let missing = ToolFinder.ffmpeg == nil
            ? "Video and audio conversions need ffmpeg (brew install ffmpeg)."
            : "All media engines are available."
        let note = NSTextField(labelWithString: missing)
        note.font = .systemFont(ofSize: 10.5)
        note.textColor = .secondaryLabelColor
        engineStack.addArrangedSubview(note)
    }

    @objc private func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an ffmpeg executable"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Prefs.setToolOverride("ffmpeg", url.path)
        refreshEngines()
    }

    @objc private func resetFFmpeg() {
        Prefs.setToolOverride("ffmpeg", "")
        refreshEngines()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func resetSettings() {
        Prefs.defaults.removePersistentDomain(forName: "com.zest.app")
        Prefs.register()
        ToolFinder.invalidate()
        syncControls()
        refreshEngines()
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }
}
