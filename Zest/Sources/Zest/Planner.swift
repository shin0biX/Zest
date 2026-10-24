import AppKit

// MARK: - Planner

enum Planner {
    static func submit(context: DragContext, choice: WheelChoice, mode: WheelMode) {
        switch choice.payload {
        case .format(let fmt):
            convert(urls: context.urls, to: fmt)
        case .tool(let id):
            runTool(id: id, urls: context.urls)
        case .action(let id):
            Actions.perform(urls: context.urls, action: id)
        }
    }

    private static func convert(urls: [URL], to fmt: Fmt) {
        let files = urls.filter { !$0.isDirectory }
        let folders = urls.filter { $0.isDirectory }
        let all = files + folders
        guard !all.isEmpty else { return }

        if fmt.ext == "zip" || fmt.ext == "tar" || fmt.ext == "gz" {
            if all.count > 1 || (all.count == 1 && all[0].isDirectory) {
                archiveBatch(urls: all, ext: fmt.ext)
                return
            }
        }

        // Several images into one PDF, rather than one PDF per source image.
        if fmt.outKind == .pdf, all.count > 1,
           all.allSatisfy({ KindDetector.kind(of: $0) == .image }) {
            let token = HUDController.shared.begin("\(all.count) images → PDF")
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outputs = try PDFEngine.fromImages(all)
                    onMain {
                        HUDController.shared.succeed(token, outputs: outputs)
                        RecentStore.record(title: "\(all.count) images → PDF",
                                            choiceId: "fmt-pdf", mode: .convert,
                                            inputs: all, outputs: outputs)
                    }
                } catch {
                    onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
                }
            }
            return
        }

        var params = Prefs.conversionParams(for: fmt)
        // Layout defaults live on the source format page (DOCX, Pages, EPUB),
        // so read them from the input rather than the output extension.
        if let source = all.first?.pathExtension.lowercased(),
           fmt.outKind == .pdf || fmt.ext.lowercased() == "epub" {
            params["pdfLayout"] = Prefs.pdfLayout(for: source)
            params["epubLayout"] = Prefs.epubLayout(for: source)
        }
        for url in all {
            let token = HUDController.shared.begin(url.lastPathComponent)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outputs = try Convert.perform(url, to: fmt, params: params)
                    onMain {
                        HUDController.shared.succeed(token, outputs: outputs)
                        RecentStore.record(title: "\(url.pathExtension.uppercased()) → \(fmt.title)",
                                            choiceId: "fmt-\(fmt.ext)", mode: .convert,
                                            inputs: [url], outputs: outputs)
                    }
                } catch {
                    onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
                }
            }
        }
    }

    private static func archiveBatch(urls: [URL], ext: String) {
        let token = HUDController.shared.begin("\(urls.count) items → \(ext.uppercased())")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let out = try ArchiveEngine.create(urls: urls, ext: ext)
                onMain {
                    HUDController.shared.succeed(token, outputs: [out])
                    RecentStore.record(title: "\(urls.count) items → \(ext.uppercased())",
                                        choiceId: "fmt-\(ext)", mode: .convert,
                                        inputs: urls, outputs: [out])
                }
            } catch {
                onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
            }
        }
    }

    private static func runTool(id: String, urls: [URL]) {
        guard let kind = KindDetector.commonKind(urls), !urls.isEmpty else {
            Alert.show("Mixed selection",
                       detail: "Choose files of one kind for this tool, or use the Actions wheel.")
            return
        }

        guard let params = ToolUI.collect(tool: id, inputs: urls, kind: kind) else { return }

        if ToolRunner.isBatch(id) {
            let token = HUDController.shared.begin(batchTitle(id: id, count: urls.count))
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outputs = try ToolRunner.run(tool: id, inputs: urls, params: params)
                    onMain { finish(token: token, tool: id, outputs: outputs, inputs: urls) }
                } catch {
                    onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
                }
            }
            return
        }

        for url in urls {
            let token = HUDController.shared.begin("\(toolTitle(id)) · \(url.lastPathComponent)")
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outputs = try ToolRunner.run(tool: id, inputs: [url], params: params)
                    onMain { finish(token: token, tool: id, outputs: outputs, inputs: [url]) }
                } catch {
                    onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
                }
            }
        }
    }

    private static func finish(token: HUDToken, tool: String, outputs: [URL],
                               inputs: [URL] = []) {
        if tool == "qr", outputs.isEmpty {
            HUDController.shared.succeed(token, outputs: [], note: "No codes found")
        } else {
            HUDController.shared.succeed(token, outputs: outputs)
            if !inputs.isEmpty {
                RecentStore.record(title: toolTitle(tool),
                                   choiceId: "tool-\(tool)", mode: .tools,
                                   inputs: inputs, outputs: outputs)
            }
        }
    }

    private static func toolTitle(_ id: String) -> String {
        let all = Catalog.imageTools + Catalog.videoTools + Catalog.audioTools
            + Catalog.pdfTools + Catalog.docTools + Catalog.subtitleTools
            + Catalog.archiveTools
        return all.first { $0.id == id }?.title ?? id
    }

    private static func batchTitle(id: String, count: Int) -> String {
        switch id {
        case "join": return "Join \(count) files"
        case "merge": return "Merge \(count) files"
        case "collage": return "Collage \(count) images"
        default: return "\(toolTitle(id)) · \(count) files"
        }
    }
}

// MARK: - Alerts

enum Alert {
    static func show(_ title: String, detail: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func error(_ title: String, _ error: Error) {
        show(title, detail: error.localizedDescription, style: .warning)
    }
}

// MARK: - Actions

enum Actions {
    static func perform(urls: [URL], action: String) {
        switch action {
        case "airdrop":
            airDrop(urls)
        case "float":
            FloatingFiles.show(urls)
        case "copy":
            duplicate(urls)
        case "move":
            move(urls)
        case "copyPath":
            let text = urls.map(\.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            toast("Copied \(urls.count == 1 ? "path" : "paths")")
        case "terminal":
            openTerminal(urls)
        case "reveal":
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        default:
            Log.write("Unknown action \(action)")
        }
    }

    private static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            Alert.show("AirDrop unavailable", detail: "This Mac cannot start an AirDrop share right now.")
            return
        }
        if !service.canPerform(withItems: urls) {
            Alert.show("AirDrop can't send these items",
                       detail: "Finder may still be able to. Try right-clicking the file and choosing Share → AirDrop.")
            return
        }
        service.perform(withItems: urls)
    }

    private static func duplicate(_ urls: [URL]) {
        let token = HUDController.shared.begin(urls.count == 1
            ? "Duplicate \(urls[0].lastPathComponent)"
            : "Duplicate \(urls.count) items")
        DispatchQueue.global(qos: .userInitiated).async {
            var outputs: [URL] = []
            do {
                for url in urls {
                    let ext = url.pathExtension
                    let dir = url.deletingLastPathComponent()
                    let stem = url.deletingPathExtension().lastPathComponent
                    var candidate = dir.appendingPathComponent("\(stem) copy\(ext.isEmpty ? "" : "." + ext)")
                    var i = 2
                    while FileManager.default.fileExists(atPath: candidate.path) {
                        candidate = dir.appendingPathComponent("\(stem) copy \(i)\(ext.isEmpty ? "" : "." + ext)")
                        i += 1
                    }
                    try FileManager.default.copyItem(at: url, to: candidate)
                    outputs.append(candidate)
                }
                onMain {
                    HUDController.shared.succeed(token, outputs: outputs)
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
            } catch {
                onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
            }
        }
    }

    private static func move(_ urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = "Choose a destination for \(urls.count == 1 ? "the item" : "\(urls.count) items")"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let token = HUDController.shared.begin("Move \(urls.count) item\(urls.count == 1 ? "" : "s")")
        DispatchQueue.global(qos: .userInitiated).async {
            var moved: [URL] = []
            do {
                for url in urls {
                    var target = destination.appendingPathComponent(url.lastPathComponent)
                    var i = 2
                    while FileManager.default.fileExists(atPath: target.path) {
                        let stem = url.deletingPathExtension().lastPathComponent
                        let ext = url.pathExtension
                        target = destination.appendingPathComponent(
                            "\(stem) \(i)\(ext.isEmpty ? "" : "." + ext)")
                        i += 1
                    }
                    try FileManager.default.moveItem(at: url, to: target)
                    moved.append(target)
                }
                onMain {
                    HUDController.shared.succeed(token, outputs: moved)
                    NSWorkspace.shared.activateFileViewerSelecting(moved)
                }
            } catch {
                onMain { HUDController.shared.fail(token, message: error.localizedDescription) }
            }
        }
    }

    private static func openTerminal(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let choice = Prefs.terminalApp
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleID)
        let candidate = resolved ?? URL(fileURLWithPath: choice.fallbackPath)
        let terminal = FileManager.default.fileExists(atPath: candidate.path)
            ? candidate
            : URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let dir = urls.count == 1 && first.isDirectory
            ? first
            : first.deletingLastPathComponent()
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([dir], withApplicationAt: terminal,
                                configuration: config) { _, error in
            if let error {
                onMain { Alert.error("Couldn't open \(choice.title)", error) }
            }
        }
    }

    private static func toast(_ message: String) {
        let token = HUDController.shared.begin(message)
        HUDController.shared.succeed(token, outputs: [], note: message)
    }
}


// MARK: - Recent conversions

/// One remembered operation, persisted to Application Support so the status
/// menu can offer "run again" and "reveal" long after the HUD closed.
struct RecentEntry: Codable {
    let title: String
    let choiceId: String
    let mode: String
    let inputPaths: [String]
    let outputPaths: [String]
    let date: Date
}

extension RecentEntry {
    /// Input URLs that still exist on disk.
    func inputPathsWithExistenceCheck() -> [URL] {
        inputPaths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum RecentStore {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
        .appendingPathComponent("Zest/recent.json")
    static let limit = 12

    static func load() -> [RecentEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RecentEntry].self, from: data)) ?? []
    }

    /// Main-thread only; the HUD success path already lands on main.
    static func record(title: String, choiceId: String, mode: WheelMode,
                       inputs: [URL], outputs: [URL]) {
        let entry = RecentEntry(title: title, choiceId: choiceId, mode: mode.rawValue,
                                inputPaths: inputs.map(\.path),
                                outputPaths: outputs.map(\.path),
                                date: Date())
        var all = [entry] + load()
        all = Array(all.prefix(limit))
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: .zestSettingsChanged, object: nil)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Rebuilds the wheel choice for an entry from the real catalog, gated by
    /// the same availability rules that built the original wheel.
    static func choice(for entry: RecentEntry, inputs: [URL]) -> WheelChoice? {
        guard let mode = WheelMode(rawValue: entry.mode) else { return nil }
        return Catalog.choices(for: inputs, mode: mode).first { $0.id == entry.choiceId }
    }
}
