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

        // First run on a fresh install: walk the new user through the drag →
        // modifier → pick flow. The window also stays reachable from
        // Settings → About for anyone who wants it again.
        if !Prefs.welcomeSeen {
            WelcomeWindow.shared.show()
        }

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
        NotificationCenter.default.addObserver(self, selector: #selector(showSettingsFromNotification),
                                               name: .zestOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: .zestSettingsChanged, object: nil)
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

    @objc private func showWelcome() {
        WelcomeWindow.shared.show()
    }

    @objc private func showSettingsFromNotification() {
        showSettings()
    }

    @objc private func prefsChanged() {
        rebuildMenu()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}

