import AppKit
import UniformTypeIdentifiers

enum TriggerKey: String, CaseIterable {
    case shift, command, control, option

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        }
    }

    var title: String {
        switch self {
        case .shift: return "Shift ⇧"
        case .command: return "Command ⌘"
        case .control: return "Control ⌃"
        case .option: return "Option ⌥"
        }
    }

    /// Compact glyph for the wheel hub and status rows.
    var glyph: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        }
    }

    var name: String {
        switch self {
        case .shift: return "Shift"
        case .command: return "Command"
        case .control: return "Control"
        case .option: return "Option"
        }
    }

    /// Popup label in the settings window.
    var settingsTitle: String { "\(glyph)  \(name)" }
}

enum AppearanceStyle: String, CaseIterable {
    case glass, solid

    var title: String {
        switch self {
        case .glass: return "Glass"
        case .solid: return "Solid"
        }
    }
}

enum WheelStyle: String, CaseIterable {
    case fan, rings

    var title: String {
        switch self {
        case .fan: return "Fan"
        case .rings: return "Rings"
        }
    }

    var detail: String {
        switch self {
        case .fan: return "One surface at a time"
        case .rings: return "All surfaces at once"
        }
    }
}

enum FloatBehavior: String, CaseIterable {
    case newFloat, addToExisting

    var title: String {
        switch self {
        case .newFloat: return "Create New Float"
        case .addToExisting: return "Add Files to Existing Float"
        }
    }
}

enum TerminalChoice: String, CaseIterable {
    case terminal, iterm, warp

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .warp: return "Warp"
        }
    }

    var bundleID: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        }
    }

    var fallbackPath: String {
        switch self {
        case .terminal: return "/System/Applications/Utilities/Terminal.app"
        case .iterm: return "/Applications/iTerm.app"
        case .warp: return "/Applications/Warp.app"
        }
    }
}

enum QualityPreset: String, CaseIterable {
    case best, higher, balanced, smaller, smallest

    var title: String {
        switch self {
        case .best: return "Best"
        case .higher: return "Higher Quality"
        case .balanced: return "Balanced"
        case .smaller: return "Smaller"
        case .smallest: return "Smallest"
        }
    }

    var value: Double {
        switch self {
        case .best: return 0.95
        case .higher: return 0.86
        case .balanced: return 0.75
        case .smaller: return 0.60
        case .smallest: return 0.45
        }
    }
}

enum ImageSizePreset: String, CaseIterable {
    case original, px4096, px2048, px1600, px1080, px720

    var title: String {
        switch self {
        case .original: return "Keep original dimensions"
        case .px4096: return "Longest edge 4096 px"
        case .px2048: return "Longest edge 2048 px"
        case .px1600: return "Longest edge 1600 px"
        case .px1080: return "Longest edge 1080 px"
        case .px720: return "Longest edge 720 px"
        }
    }

    var pixels: Int {
        switch self {
        case .original: return 0
        case .px4096: return 4096
        case .px2048: return 2048
        case .px1600: return 1600
        case .px1080: return 1080
        case .px720: return 720
        }
    }
}

enum VideoHeightPreset: String, CaseIterable {
    case original, px2160, px1080, px720, px480

    var title: String {
        switch self {
        case .original: return "Keep original height"
        case .px2160: return "Maximum 2160p"
        case .px1080: return "Maximum 1080p"
        case .px720: return "Maximum 720p"
        case .px480: return "Maximum 480p"
        }
    }

    var pixels: Int {
        switch self {
        case .original: return 0
        case .px2160: return 2160
        case .px1080: return 1080
        case .px720: return 720
        case .px480: return 480
        }
    }
}

enum Prefs {
    /// The shipping bundle owns `com.zest.app`, so its standard domain already
    /// is that suite; asking for the suite by name logs a warning and is a
    /// no-op. Headless binaries have no bundle identifier, so they do need the
    /// named suite to share the same preferences.
    static let defaults: UserDefaults = {
        let suite = "com.zest.app"
        if Bundle.main.bundleIdentifier == suite { return .standard }
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    static func register() {
        defaults.register(defaults: [
            "key.convert": TriggerKey.shift.rawValue,
            "key.tools": TriggerKey.command.rawValue,
            "key.actions": TriggerKey.control.rawValue,
            "collision": "keepBoth",
            "sound": true,
            "quality": "balanced",
            "keyboardControl": false,
            "appearance": AppearanceStyle.glass.rawValue,
            "wheelStyle": WheelStyle.rings.rawValue,
            "floatBehavior": FloatBehavior.newFloat.rawValue,
            "terminalApp": TerminalChoice.terminal.rawValue,
            "launchAtLogin": false,
            "welcomeSeen": false,
            "verboseLog": false,
            "format.preserveMetadata": true,
            "format.imageCompression": "balanced",
            "format.imageSize": ImageSizePreset.original.rawValue,
            "format.videoHeight": VideoHeightPreset.original.rawValue,
            "format.videoQuality": QualityPreset.balanced.rawValue,
            "format.audioBitrate": "192",
            "format.audioBitDepth": "16",
            "format.gifFPS": "12",
            "format.gifWidth": "720",
            "format.pdfLayout": "editable",
            "format.epubLayout": "flowing"
        ])
    }

    static var convertKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: "key.convert") ?? "") ?? .shift }
        set { defaults.set(newValue.rawValue, forKey: "key.convert") }
    }

    static var toolsKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: "key.tools") ?? "") ?? .command }
        set { defaults.set(newValue.rawValue, forKey: "key.tools") }
    }

    static var actionsKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: "key.actions") ?? "") ?? .control }
        set { defaults.set(newValue.rawValue, forKey: "key.actions") }
    }

    static var collisionPolicy: String {
        get { defaults.string(forKey: "collision") ?? "keepBoth" }
        set { defaults.set(newValue, forKey: "collision") }
    }

    static var playSound: Bool {
        get { defaults.object(forKey: "sound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sound") }
    }

    static var quality: String {
        get { defaults.string(forKey: "quality") ?? "balanced" }
        set { defaults.set(newValue, forKey: "quality") }
    }

    static var keyboardControl: Bool {
        get { defaults.object(forKey: "keyboardControl") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "keyboardControl") }
    }

    static var appearance: AppearanceStyle {
        get { AppearanceStyle(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .glass }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }

    static var wheelStyle: WheelStyle {
        get { WheelStyle(rawValue: defaults.string(forKey: "wheelStyle") ?? "") ?? .rings }
        set { defaults.set(newValue.rawValue, forKey: "wheelStyle") }
    }

    static var floatBehavior: FloatBehavior {
        get { FloatBehavior(rawValue: defaults.string(forKey: "floatBehavior") ?? "") ?? .newFloat }
        set { defaults.set(newValue.rawValue, forKey: "floatBehavior") }
    }

    static var terminalApp: TerminalChoice {
        get { TerminalChoice(rawValue: defaults.string(forKey: "terminalApp") ?? "") ?? .terminal }
        set { defaults.set(newValue.rawValue, forKey: "terminalApp") }
    }

    static var launchAtLogin: Bool {
        get { defaults.object(forKey: "launchAtLogin") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    static var welcomeSeen: Bool {
        get { defaults.object(forKey: "welcomeSeen") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "welcomeSeen") }
    }

    /// Drag-trace logging for development and the external harness. Release
    /// builds stay quiet unless this is set (the harness sets it for its
    /// run). Errors always log.
    static var verboseLog: Bool {
        get { defaults.object(forKey: "verboseLog") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "verboseLog") }
    }

    // MARK: Per-format defaults
    //
    // Each key is namespaced by the output extension so a JPG default never
    // leaks into PNG or HEIC. Missing values fall back to the defaults
    // registered above.

    private static func key(_ name: String, _ ext: String) -> String {
        "format.\(name).\(ext.lowercased())"
    }

    static func qualityPreset(for ext: String) -> QualityPreset {
        if let raw = defaults.string(forKey: key("quality", ext)),
           let preset = QualityPreset(rawValue: raw) { return preset }
        return .balanced
    }

    static func setQualityPreset(_ preset: QualityPreset, for ext: String) {
        defaults.set(preset.rawValue, forKey: key("quality", ext))
    }

    static func preserveMetadata(for ext: String) -> Bool {
        if defaults.object(forKey: key("preserveMetadata", ext)) == nil {
            return defaults.object(forKey: "format.preserveMetadata") as? Bool ?? true
        }
        return defaults.bool(forKey: key("preserveMetadata", ext))
    }

    static func setPreserveMetadata(_ value: Bool, for ext: String) {
        defaults.set(value, forKey: key("preserveMetadata", ext))
    }

    static func imageCompression(for ext: String) -> String {
        defaults.string(forKey: key("imageCompression", ext))
            ?? defaults.string(forKey: "format.imageCompression") ?? "balanced"
    }

    static func setImageCompression(_ value: String, for ext: String) {
        defaults.set(value, forKey: key("imageCompression", ext))
    }

    static func imageSize(for ext: String) -> ImageSizePreset {
        let raw = defaults.string(forKey: key("imageSize", ext))
            ?? defaults.string(forKey: "format.imageSize") ?? ""
        return ImageSizePreset(rawValue: raw) ?? .original
    }

    static func setImageSize(_ preset: ImageSizePreset, for ext: String) {
        defaults.set(preset.rawValue, forKey: key("imageSize", ext))
    }

    static func videoQuality(for ext: String) -> QualityPreset {
        let raw = defaults.string(forKey: key("videoQuality", ext))
            ?? defaults.string(forKey: "format.videoQuality") ?? ""
        return QualityPreset(rawValue: raw) ?? .balanced
    }

    static func setVideoQuality(_ preset: QualityPreset, for ext: String) {
        defaults.set(preset.rawValue, forKey: key("videoQuality", ext))
    }

    static func videoHeight(for ext: String) -> VideoHeightPreset {
        let raw = defaults.string(forKey: key("videoHeight", ext))
            ?? defaults.string(forKey: "format.videoHeight") ?? ""
        return VideoHeightPreset(rawValue: raw) ?? .original
    }

    static func setVideoHeight(_ preset: VideoHeightPreset, for ext: String) {
        defaults.set(preset.rawValue, forKey: key("videoHeight", ext))
    }

    static func audioBitrate(for ext: String) -> String {
        defaults.string(forKey: key("audioBitrate", ext))
            ?? defaults.string(forKey: "format.audioBitrate") ?? "192"
    }

    static func setAudioBitrate(_ value: String, for ext: String) {
        defaults.set(value, forKey: key("audioBitrate", ext))
    }

    static func audioBitDepth(for ext: String) -> String {
        defaults.string(forKey: key("audioBitDepth", ext))
            ?? defaults.string(forKey: "format.audioBitDepth") ?? "16"
    }

    static func setAudioBitDepth(_ value: String, for ext: String) {
        defaults.set(value, forKey: key("audioBitDepth", ext))
    }

    static func gifFPS(for ext: String) -> Int {
        Int(defaults.string(forKey: key("gifFPS", ext))
            ?? defaults.string(forKey: "format.gifFPS") ?? "12") ?? 12
    }

    static func gifWidth(for ext: String) -> Int {
        Int(defaults.string(forKey: key("gifWidth", ext))
            ?? defaults.string(forKey: "format.gifWidth") ?? "720") ?? 720
    }

    static func setGIF(fps: Int, width: Int, for ext: String) {
        defaults.set("\(fps)", forKey: key("gifFPS", ext))
        defaults.set("\(width)", forKey: key("gifWidth", ext))
    }

    static func pdfLayout(for ext: String) -> String {
        defaults.string(forKey: key("pdfLayout", ext))
            ?? defaults.string(forKey: "format.pdfLayout") ?? "editable"
    }

    static func setPDFLayout(_ value: String, for ext: String) {
        defaults.set(value, forKey: key("pdfLayout", ext))
    }

    static func epubLayout(for ext: String) -> String {
        // The EPUB page stores `format.epubLayout.epub`; any source that
        // converts *to* EPUB (PDF, DOCX) should honour it.
        defaults.string(forKey: key("epubLayout", ext))
            ?? defaults.string(forKey: key("epubLayout", "epub"))
            ?? defaults.string(forKey: "format.epubLayout") ?? "flowing"
    }

    static func setEPUBLayout(_ value: String, for ext: String) {
        defaults.set(value, forKey: key("epubLayout", ext))
    }

    static func resetFormatDefaults(_ ext: String) {
        for name in ["quality", "preserveMetadata", "imageCompression", "imageSize",
                     "videoQuality", "videoHeight", "audioBitrate", "audioBitDepth",
                     "gifFPS", "gifWidth", "pdfLayout", "epubLayout"] {
            defaults.removeObject(forKey: key(name, ext))
        }
    }

    /// Restores only the image compression and sizing controls, matching the
    /// separate "Restore Compression Defaults" action in the reference UI.
    static func resetImageDefaults(_ ext: String) {
        for name in ["imageCompression", "imageSize"] {
            defaults.removeObject(forKey: key(name, ext))
        }
    }

    /// Params passed into `Convert.perform` for a committed format.
    static func conversionParams(for fmt: Fmt) -> [String: String] {
        let ext = fmt.ext.lowercased()
        var params: [String: String] = [:]

        switch fmt.outKind {
        case .image:
            let quality = qualityPreset(for: ext)
            params["quality"] = "\(quality.value)"
            params["preserveMetadata"] = preserveMetadata(for: ext) ? "1" : "0"
            params["imageCompression"] = imageCompression(for: ext)
            let size = imageSize(for: ext).pixels
            if size > 0 { params["maxDimension"] = "\(size)" }
            if ext == "gif" {
                params["fps"] = "\(gifFPS(for: ext))"
                params["width"] = "\(gifWidth(for: ext))"
            }
        case .video:
            params["quality"] = videoQuality(for: ext).rawValue
            params["crf"] = "\(crf(for: videoQuality(for: ext)))"
            let height = videoHeight(for: ext).pixels
            if height > 0 { params["maxHeight"] = "\(height)" }
            params["audioBitrate"] = audioBitrate(for: ext) + "k"
        case .audio:
            params["audioBitrate"] = audioBitrate(for: ext) + "k"
            params["audioBitDepth"] = audioBitDepth(for: ext)
        case .document:
            params["pdfLayout"] = pdfLayout(for: ext)
            params["epubLayout"] = epubLayout(for: ext)
        default:
            break
        }
        return params
    }

    private static func crf(for preset: QualityPreset) -> Int {
        switch preset {
        case .best: return 16
        case .higher: return 20
        case .balanced: return 23
        case .smaller: return 28
        case .smallest: return 32
        }
    }

    static func toolOverride(_ name: String) -> String? {
        let value = defaults.string(forKey: "tool.\(name)") ?? ""
        return value.isEmpty ? nil : value
    }

    static func setToolOverride(_ name: String, _ path: String) {
        defaults.set(path, forKey: "tool.\(name)")
    }
}

enum Capability {
    static var ffmpeg: Bool { ToolFinder.ffmpeg != nil }
    /// Some ffmpeg builds ship without libvorbis (this host's Homebrew does),
    /// which makes OGG output impossible — the wheel must not offer it then.
    static let vorbisEncode: Bool = {
        guard let ffmpeg = ToolFinder.ffmpeg,
              let list = try? Shell.run(ffmpeg, ["-hide_banner", "-encoders"]) else {
            return false
        }
        return list.contains("libvorbis")
    }()
    static var webpEncode: Bool { ToolFinder.cwebp != nil || ffmpeg }
    static var avifEncode: Bool { ffmpeg || ImageSupport.canEncode("avif") }
    static var officeExport: Bool { ToolFinder.soffice != nil }
    static var pagesOutput: Bool { FileManager.default.fileExists(atPath: "/Applications/Pages.app") }
    static var rarInput: Bool { ToolFinder.find("unar") != nil || ToolFinder.find("unrar") != nil }
}

enum ImageSupport {
    static let destinationTypes: Set<String> = {
        (CGImageDestinationCopyTypeIdentifiers() as? [String]).map(Set.init) ?? []
    }()

    static func canEncode(_ ext: String) -> Bool {
        guard let ut = UTType(filenameExtension: ext) else { return false }
        return destinationTypes.contains(ut.identifier)
    }
}
