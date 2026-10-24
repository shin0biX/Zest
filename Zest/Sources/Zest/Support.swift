import AppKit
import UniformTypeIdentifiers

// MARK: - Logging

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Zest.log")

    private static let lock = NSLock()

    /// Drag-trace lines. Debug builds log them; release builds stay quiet
    /// unless `com.zest.app verboseLog -bool true` is set (the external
    /// harness flips it on for its run). Errors use `write` directly.
    static func verbose(_ message: String) {
        #if DEBUG
        write(message)
        #else
        if Prefs.verboseLog { write(message) }
        #endif
    }

    static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let line = "[\(df.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}

// MARK: - Errors

struct ZestError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Shell

enum Shell {
    @discardableResult
    static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let (status, output) = try runAllowFailure(tool, args, cwd: cwd)
        if status != 0 {
            throw ZestError("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(status)): \(output.suffix(1200))")
        }
        return output
    }

    static func runAllowFailure(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["LC_ALL"] = "en_US.UTF-8"
        env["COPYFILE_DISABLE"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func which(_ name: String) -> String? {
        ToolFinder.find(name)
    }
}

// MARK: - Tool discovery

enum ToolFinder {
    private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    static func find(_ name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name] { return hit }

        var candidates: [String] = []
        if let res = Bundle.main.resourcePath {
            candidates.append("\(res)/Tools/\(name)")
        }
        if let override = Prefs.toolOverride(name), !override.isEmpty {
            candidates.insert(override, at: 0)
        }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                    "/usr/sbin", "/sbin",
                    "/Applications/LibreOffice.app/Contents/MacOS"] {
            candidates.append("\(dir)/\(name)")
        }
        if let path = resolve(name, candidates: candidates) {
            cache[name] = path
            return path
        }

        // Last resort: ask a login shell (GUI apps do not inherit PATH).
        let shell = "/bin/zsh"
        if FileManager.default.isExecutableFile(atPath: shell),
           let result = try? Shell.runAllowFailure(shell, ["-lc", "command -v \(name)"]),
           result.0 == 0 {
            let path = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, launches(path, name: name) {
                cache[name] = path
                return path
            }
        }
        cache[name] = nil
        return nil
    }

    /// First candidate that is executable **and** starts cleanly. A bundled
    /// binary can be present but unusable (wrong architecture, broken
    /// signature, expired build); without this check it would shadow the
    /// working Homebrew copy.
    static func resolve(_ name: String, candidates: [String]) -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if launches(path, name: name) { return path }
        }
        return nil
    }

    /// Runs the tool's version flag with a short timeout. Cached by `find`.
    static func launches(_ path: String, name: String) -> Bool {
        let arguments: [String]
        switch name {
        case "ffmpeg", "ffprobe", "cwebp": arguments = ["-version"]
        case "pandoc": arguments = ["--version"]
        case "exiftool": arguments = ["-ver"]
        case "soffice": arguments = ["--version"]
        default: arguments = ["-version"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    static var ffmpeg: String? { find("ffmpeg") }
    static var ffprobe: String? { find("ffprobe") }
    static var cwebp: String? { find("cwebp") }
    static var pandoc: String? { find("pandoc") }
    static var soffice: String? { find("soffice") }
    static var exiftool: String? { find("exiftool") }
}

// MARK: - Kind

enum Kind: String {
    case image, video, audio, pdf, document, slides, sheet, subtitle, archive, folder, other

    var title: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .document: return "Document"
        case .slides: return "Slides"
        case .sheet: return "Spreadsheet"
        case .subtitle: return "Subtitles"
        case .archive: return "Archive"
        case .folder: return "Folder"
        case .other: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .slides: return "rectangle.on.rectangle"
        case .sheet: return "tablecells"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }

    var plural: String { title + (self == .subtitle ? "" : "s") }
}

enum KindDetector {
    static let imageIn: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "avif", "tiff", "tif", "bmp", "gif", "svg", "jp2", "j2k", "dng", "cr2", "nef", "arw", "raf", "orf", "rw2"]
    static let videoIn: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "ts", "mts", "3gp", "ogv"]
    static let audioIn: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "aac", "caf", "m4b", "ape"]
    static let docIn: Set<String> = ["doc", "docx", "rtf", "rtfd", "html", "htm", "md", "markdown", "txt", "text", "odt", "pages", "epub", "webarchive"]
    static let slidesIn: Set<String> = ["ppt", "pptx", "key", "odp"]
    static let sheetIn: Set<String> = ["xlsx", "xls", "ods", "csv", "tsv", "numbers"]
    static let subIn: Set<String> = ["srt", "vtt", "sbv"]
    static let archiveIn: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "rar", "7z"]

    static func kind(of url: URL) -> Kind {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return .folder }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageIn.contains(ext) { return .image }
        if videoIn.contains(ext) { return .video }
        if audioIn.contains(ext) { return .audio }
        if subIn.contains(ext) { return .subtitle }
        if archiveIn.contains(ext) { return .archive }
        if slidesIn.contains(ext) { return .slides }
        if sheetIn.contains(ext) { return .sheet }
        if docIn.contains(ext) { return .document }
        return .other
    }

    static func commonKind(_ urls: [URL]) -> Kind? {
        let kinds = Set(urls.map { kind(of: $0) })
        if kinds.count == 1 { return kinds.first }
        return nil
    }
}

// MARK: - Output naming

enum AppIcon {
    /// The icon declared by the bundle. Headless runs execute outside a
    /// bundle, so fall back to the repository copy before the generic file
    /// icon, which keeps `settings-preview` honest.
    static var image: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.icns")
        if let image = NSImage(contentsOf: local) { return image }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

enum Naming {
    static func output(for input: URL, ext: String, suffix: String? = nil, directory: URL? = nil) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let tagged = suffix.map { "\(stem)-\($0)" } ?? stem
        let base = dir.appendingPathComponent("\(tagged).\(ext)")
        if Prefs.collisionPolicy == "replace" { return base }
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        var i = 2
        while true {
            let candidate = dir.appendingPathComponent("\(tagged) \(i).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    static func batchOutput(for inputs: [URL], ext: String, suffix: String? = nil) -> URL {
        let dir = inputs.first?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        let stem = inputs.count == 1
            ? inputs[0].deletingPathExtension().lastPathComponent
            : "Archive"
        let tagged = suffix.map { "\(stem)-\($0)" } ?? stem
        var candidate = dir.appendingPathComponent("\(tagged).\(ext)")
        if Prefs.collisionPolicy == "replace" { return candidate }
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(tagged) \(i).\(ext)")
            i += 1
        }
        return candidate
    }
}

// MARK: - Temp

enum Temp {
    static func dir(prefix: String = "zest") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func clean(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - File helpers

extension URL {
    var isDirectory: Bool {
        var d: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &d)
        return d.boolValue
    }

    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }

    func ensureParent() {
        try? FileManager.default.createDirectory(
            at: deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func replacingExtension(_ ext: String) -> URL {
        deletingPathExtension().appendingPathExtension(ext)
    }
}

enum Bytes {
    static func format(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    /// Parses "500kb", "2.5 MB", "1g".
    static func parse(_ text: String) -> Int64? {
        let t = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return nil }
        let units: [(String, Double)] = [
            ("tb", 1e12), ("gb", 1e9), ("mb", 1e6), ("kb", 1e3),
            ("t", 1e12), ("g", 1e9), ("m", 1e6), ("k", 1e3), ("b", 1)
        ]
        for (suffix, mult) in units where t.hasSuffix(suffix) {
            if let v = Double(t.dropLast(suffix.count)) { return Int64(v * mult) }
        }
        if let v = Double(t) { return Int64(v) }
        return nil
    }
}

// MARK: - Duration

enum MediaProbe {
    struct Info {
        var duration: Double = 0
        var width: Int = 0
        var height: Int = 0
        var hasAudio = false
        var hasVideo = false
        var fps: Double = 0
        var bitrate: Double = 0
    }

    static func info(_ url: URL) -> Info {
        var info = Info()
        guard let ffprobe = ToolFinder.ffprobe else { return info }
        guard let result = try? Shell.runAllowFailure(ffprobe, [
            "-v", "error", "-show_entries",
            "format=duration,bit_rate:stream=codec_type,width,height,r_frame_rate",
            "-of", "default=noprint_wrappers=1", url.path
        ]), result.0 == 0 else { return info }
        for line in result.1.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "duration": info.duration = Double(parts[1]) ?? 0
            case "bit_rate": info.bitrate = Double(parts[1]) ?? 0
            case "codec_type":
                if parts[1] == "audio" { info.hasAudio = true }
                if parts[1] == "video" { info.hasVideo = true }
            case "width": info.width = Int(parts[1]) ?? 0
            case "height": info.height = Int(parts[1]) ?? 0
            case "r_frame_rate":
                let bits = parts[1].split(separator: "/").compactMap { Double($0) }
                if bits.count == 2, bits[1] != 0 { info.fps = bits[0] / bits[1] }
            default: break
            }
        }
        return info
    }
}

// MARK: - Small UI helpers

extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
}

func onMainSync(_ block: () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.sync(execute: block) }
}
