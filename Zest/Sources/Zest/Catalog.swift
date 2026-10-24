import AppKit
import UniformTypeIdentifiers

// MARK: - Format

struct Fmt {
    let ext: String
    let title: String
    let outKind: Kind
    let symbol: String
}

enum WheelMode: String {
    case convert, tools, actions

    var title: String {
        switch self {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    /// One activation colour for every mode: the device's lime. Green means
    /// selected/armed wherever the wheel shows it.
    var accent: NSColor { Omnitrix.lime }
}

struct WheelChoice {
    enum Payload {
        case format(Fmt)
        case tool(String)
        case action(String)
    }
    let id: String
    let title: String
    let symbol: String
    let hint: String
    let payload: Payload
}

struct ToolDef {
    let id: String
    let title: String
    let symbol: String
    let hint: String
}

// MARK: - Catalog

enum Catalog {
    // Output formats. `outKind` drives which engine runs.
    static let imageOut: [Fmt] = [
        Fmt(ext: "png", title: "PNG", outKind: .image, symbol: "photo"),
        Fmt(ext: "jpg", title: "JPG", outKind: .image, symbol: "photo"),
        Fmt(ext: "heic", title: "HEIC", outKind: .image, symbol: "photo"),
        Fmt(ext: "webp", title: "WebP", outKind: .image, symbol: "photo"),
        Fmt(ext: "avif", title: "AVIF", outKind: .image, symbol: "photo"),
        Fmt(ext: "tiff", title: "TIFF", outKind: .image, symbol: "photo"),
        Fmt(ext: "bmp", title: "BMP", outKind: .image, symbol: "photo"),
        Fmt(ext: "gif", title: "GIF", outKind: .image, symbol: "photo"),
        Fmt(ext: "pdf", title: "PDF", outKind: .pdf, symbol: "doc.richtext")
    ]

    static let videoOut: [Fmt] = [
        Fmt(ext: "mp4", title: "MP4", outKind: .video, symbol: "film"),
        Fmt(ext: "mov", title: "MOV", outKind: .video, symbol: "film"),
        Fmt(ext: "mkv", title: "MKV", outKind: .video, symbol: "film"),
        Fmt(ext: "webm", title: "WebM", outKind: .video, symbol: "film"),
        Fmt(ext: "avi", title: "AVI", outKind: .video, symbol: "film"),
        Fmt(ext: "wmv", title: "WMV", outKind: .video, symbol: "film"),
        Fmt(ext: "gif", title: "GIF", outKind: .image, symbol: "photo"),
        Fmt(ext: "mp3", title: "MP3", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "m4a", title: "M4A", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "wav", title: "WAV", outKind: .audio, symbol: "music.note")
    ]

    static let audioOut: [Fmt] = [
        Fmt(ext: "mp3", title: "MP3", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "m4a", title: "M4A", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "wav", title: "WAV", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "flac", title: "FLAC", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "ogg", title: "OGG", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "opus", title: "Opus", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "aiff", title: "AIFF", outKind: .audio, symbol: "music.note"),
        Fmt(ext: "wma", title: "WMA", outKind: .audio, symbol: "music.note")
    ]

    static let pdfOut: [Fmt] = [
        Fmt(ext: "docx", title: "DOCX", outKind: .document, symbol: "doc.text"),
        Fmt(ext: "pptx", title: "PPTX", outKind: .slides, symbol: "rectangle.on.rectangle"),
        Fmt(ext: "xlsx", title: "XLSX", outKind: .sheet, symbol: "tablecells"),
        Fmt(ext: "jpg", title: "JPG", outKind: .image, symbol: "photo"),
        Fmt(ext: "png", title: "PNG", outKind: .image, symbol: "photo"),
        Fmt(ext: "txt", title: "TXT", outKind: .document, symbol: "doc.plaintext"),
        Fmt(ext: "md", title: "Markdown", outKind: .document, symbol: "text.alignleft"),
        Fmt(ext: "epub", title: "EPUB", outKind: .document, symbol: "book")
    ]

    static let documentOut: [Fmt] = [
        Fmt(ext: "pdf", title: "PDF", outKind: .pdf, symbol: "doc.richtext"),
        Fmt(ext: "docx", title: "DOCX", outKind: .document, symbol: "doc.text"),
        Fmt(ext: "txt", title: "TXT", outKind: .document, symbol: "doc.plaintext"),
        Fmt(ext: "md", title: "Markdown", outKind: .document, symbol: "text.alignleft"),
        Fmt(ext: "rtf", title: "RTF", outKind: .document, symbol: "doc.richtext"),
        Fmt(ext: "html", title: "HTML", outKind: .document, symbol: "chevron.left.forwardslash.chevron.right"),
        Fmt(ext: "epub", title: "EPUB", outKind: .document, symbol: "book")
    ]

    static let slidesOut: [Fmt] = [
        Fmt(ext: "pdf", title: "PDF", outKind: .pdf, symbol: "doc.richtext"),
        Fmt(ext: "png", title: "PNG", outKind: .image, symbol: "photo"),
        Fmt(ext: "jpg", title: "JPG", outKind: .image, symbol: "photo")
    ]

    static let sheetOut: [Fmt] = [
        Fmt(ext: "csv", title: "CSV", outKind: .sheet, symbol: "tablecells"),
        Fmt(ext: "tsv", title: "TSV", outKind: .sheet, symbol: "tablecells"),
        Fmt(ext: "xlsx", title: "XLSX", outKind: .sheet, symbol: "tablecells"),
        Fmt(ext: "ods", title: "ODS", outKind: .sheet, symbol: "tablecells"),
        Fmt(ext: "pdf", title: "PDF", outKind: .pdf, symbol: "doc.richtext")
    ]

    static let subtitleOut: [Fmt] = [
        Fmt(ext: "srt", title: "SRT", outKind: .subtitle, symbol: "captions.bubble"),
        Fmt(ext: "vtt", title: "VTT", outKind: .subtitle, symbol: "captions.bubble"),
        Fmt(ext: "txt", title: "TXT", outKind: .document, symbol: "doc.plaintext")
    ]

    static let archiveOut: [Fmt] = [
        Fmt(ext: "zip", title: "ZIP", outKind: .archive, symbol: "archivebox"),
        Fmt(ext: "tar", title: "TAR", outKind: .archive, symbol: "archivebox"),
        Fmt(ext: "gz", title: "GZIP", outKind: .archive, symbol: "archivebox")
    ]

    static func formats(for kind: Kind) -> [Fmt] {
        switch kind {
        case .image: return imageOut
        case .video: return Capability.ffmpeg ? videoOut : []
        case .audio: return Capability.ffmpeg ? audioOut : []
        case .pdf: return pdfOut
        case .document: return documentOut + (Capability.pagesOutput
            ? [Fmt(ext: "pages", title: "Pages", outKind: .document, symbol: "doc.text")]
            : [])
        case .slides: return Capability.officeExport ? slidesOut : []
        case .sheet: return sheetOut
        case .subtitle: return subtitleOut
        case .archive, .folder: return archiveOut
        case .other: return []
        }
    }

    static func availableFormats(for urls: [URL]) -> [Fmt] {
        guard let kind = KindDetector.commonKind(urls) else { return [] }
        let sources = Set(urls.map { $0.pathExtension.lowercased() })
        return formats(for: kind).filter { fmt in
            if sources.count == 1, sources.contains(fmt.ext) { return false }
            if kind == .image, fmt.ext == "avif", !Capability.avifEncode { return false }
            if kind == .image, fmt.ext == "webp", !Capability.webpEncode { return false }
            if fmt.ext == "ogg", !Capability.vorbisEncode { return false }
            if kind == .archive, sources.contains("rar"), !Capability.rarInput { return false }
            return true
        }
    }

    // MARK: Tools

    static let imageTools: [ToolDef] = [
        ToolDef(id: "compress", title: "Compress", symbol: "arrow.down.circle", hint: "Shrink file size"),
        ToolDef(id: "targetSize", title: "Exact Size", symbol: "arrow.down.to.line", hint: "Hit a byte target"),
        ToolDef(id: "resize", title: "Resize", symbol: "arrow.up.left.and.arrow.down.right", hint: "Change dimensions"),
        ToolDef(id: "crop", title: "Crop", symbol: "crop", hint: "Trim edges"),
        ToolDef(id: "frame", title: "Add BG", symbol: "rectangle.inset.filled", hint: "Frame on a background"),
        ToolDef(id: "rotate", title: "Rotate", symbol: "rotate.right", hint: "Turn the image"),
        ToolDef(id: "flip", title: "Flip", symbol: "arrow.left.arrow.right", hint: "Mirror"),
        ToolDef(id: "adjust", title: "Adjust", symbol: "slider.horizontal.3", hint: "Light and color"),
        ToolDef(id: "grayscale", title: "Grayscale", symbol: "circle.lefthalf.filled", hint: "Black and white"),
        ToolDef(id: "annotate", title: "Annotate", symbol: "pencil.tip", hint: "Draw on the photo"),
        ToolDef(id: "redact", title: "Redact", symbol: "eye.slash", hint: "Cover sensitive areas"),
        ToolDef(id: "metadata", title: "Metadata", symbol: "info.circle", hint: "Inspect and edit"),
        ToolDef(id: "strip", title: "Strip Tags", symbol: "eraser", hint: "Remove all metadata"),
        ToolDef(id: "collage", title: "Collage", symbol: "rectangle.3.group", hint: "Combine photos"),
        ToolDef(id: "qr", title: "Read QR", symbol: "qrcode.viewfinder", hint: "Decode barcodes")
    ]

    static let videoTools: [ToolDef] = [
        ToolDef(id: "compress", title: "Compress", symbol: "arrow.down.circle", hint: "Shrink the video"),
        ToolDef(id: "targetSize", title: "Exact Size", symbol: "arrow.down.to.line", hint: "Hit a byte target"),
        ToolDef(id: "trim", title: "Trim", symbol: "scissors", hint: "Cut a range"),
        ToolDef(id: "split", title: "Split", symbol: "square.split.2x1", hint: "Break into parts"),
        ToolDef(id: "join", title: "Join", symbol: "link", hint: "Merge clips"),
        ToolDef(id: "speed", title: "Speed", symbol: "speedometer", hint: "Slow or fast"),
        ToolDef(id: "crop", title: "Crop", symbol: "crop", hint: "Cut the frame"),
        ToolDef(id: "rotate", title: "Rotate", symbol: "rotate.right", hint: "Turn the frame"),
        ToolDef(id: "snapshot", title: "Snapshot", symbol: "camera", hint: "Grab one frame"),
        ToolDef(id: "snapshots", title: "Snapshots", symbol: "camera.viewfinder", hint: "Grab several frames"),
        ToolDef(id: "gif", title: "Make GIF", symbol: "photo.stack", hint: "Loop a clip"),
        ToolDef(id: "mute", title: "Mute", symbol: "speaker.slash", hint: "Remove audio"),
        ToolDef(id: "redactVideo", title: "Redact", symbol: "eye.slash", hint: "Hide a region over time"),
        ToolDef(id: "extractAudio", title: "Extract Audio", symbol: "music.note", hint: "Rip the soundtrack"),
        ToolDef(id: "metadata", title: "Metadata", symbol: "info.circle", hint: "Inspect and edit"),
        ToolDef(id: "strip", title: "Strip Tags", symbol: "eraser", hint: "Remove all tags")
    ]

    static let audioTools: [ToolDef] = [
        ToolDef(id: "compress", title: "Compress", symbol: "arrow.down.circle", hint: "Shrink the audio"),
        ToolDef(id: "targetSize", title: "Exact Size", symbol: "arrow.down.to.line", hint: "Hit a byte target"),
        ToolDef(id: "trim", title: "Trim", symbol: "scissors", hint: "Cut a range"),
        ToolDef(id: "split", title: "Split", symbol: "square.split.2x1", hint: "Break into parts"),
        ToolDef(id: "join", title: "Join", symbol: "link", hint: "Merge tracks"),
        ToolDef(id: "normalize", title: "Normalize", symbol: "waveform", hint: "Even out loudness"),
        ToolDef(id: "bleep", title: "Bleep", symbol: "speaker.slash", hint: "Silence a range"),
        ToolDef(id: "redactAudio", title: "Redact", symbol: "eye.slash", hint: "Tone out a range"),
        ToolDef(id: "audioToVideo", title: "To Video", symbol: "film", hint: "Pair with a still"),
        ToolDef(id: "channels", title: "Channels", symbol: "speaker.wave.2", hint: "Mono or stereo"),
        ToolDef(id: "sampleRate", title: "Sample Rate", symbol: "metronome", hint: "Resample"),
        ToolDef(id: "speed", title: "Speed", symbol: "speedometer", hint: "Slow or fast"),
        ToolDef(id: "metadata", title: "Metadata", symbol: "info.circle", hint: "Inspect and edit"),
        ToolDef(id: "strip", title: "Strip Tags", symbol: "eraser", hint: "Remove all tags")
    ]

    static let pdfTools: [ToolDef] = [
        ToolDef(id: "compress", title: "Compress", symbol: "arrow.down.circle", hint: "Shrink the PDF"),
        ToolDef(id: "targetSize", title: "Exact Size", symbol: "arrow.down.to.line", hint: "Hit a byte target"),
        ToolDef(id: "merge", title: "Merge", symbol: "link", hint: "Join PDFs"),
        ToolDef(id: "split", title: "Split", symbol: "square.split.2x1", hint: "Separate pages"),
        ToolDef(id: "reorder", title: "Reorganize", symbol: "arrow.up.arrow.down", hint: "Reorder pages"),
        ToolDef(id: "rotate", title: "Rotate", symbol: "rotate.right", hint: "Turn pages"),
        ToolDef(id: "extractImages", title: "Extract Images", symbol: "photo.stack", hint: "Pull page images"),
        ToolDef(id: "metadata", title: "Metadata", symbol: "info.circle", hint: "Inspect and edit"),
        ToolDef(id: "strip", title: "Strip Tags", symbol: "eraser", hint: "Remove all tags"),
        ToolDef(id: "qr", title: "Read QR", symbol: "qrcode.viewfinder", hint: "Decode barcodes")
    ]

    static let archiveTools: [ToolDef] = [
        ToolDef(id: "extract", title: "Extract", symbol: "archivebox", hint: "Unpack beside the archive")
    ]

    static let docTools: [ToolDef] = [
        ToolDef(id: "metadata", title: "Metadata", symbol: "info.circle", hint: "Inspect and edit"),
        ToolDef(id: "strip", title: "Strip Tags", symbol: "eraser", hint: "Remove all tags")
    ]

    static let sheetTools: [ToolDef] = [
        ToolDef(id: "metadata", title: "Metadata", symbol: "info.circle", hint: "Inspect and edit"),
        ToolDef(id: "strip", title: "Strip Tags", symbol: "eraser", hint: "Remove all tags")
    ]

    static let subtitleTools: [ToolDef] = [
        ToolDef(id: "shift", title: "Shift Time", symbol: "clock.arrow.circlepath", hint: "Offset subtitles"),
        ToolDef(id: "merge", title: "Merge", symbol: "link", hint: "Join subtitle files")
    ]

    static func tools(for kind: Kind) -> [ToolDef] {
        switch kind {
        case .image: return imageTools
        case .video: return Capability.ffmpeg ? videoTools : []
        case .audio: return Capability.ffmpeg ? audioTools : []
        case .pdf: return pdfTools
        case .document: return docTools
        case .slides: return docTools
        case .sheet: return sheetTools
        case .subtitle: return subtitleTools
        case .archive: return archiveTools
        case .folder, .other: return []
        }
    }

    static let actions: [ToolDef] = [
        ToolDef(id: "airdrop", title: "AirDrop", symbol: "square.and.arrow.up", hint: "Send to a device"),
        ToolDef(id: "float", title: "Float", symbol: "macwindow.on.rectangle", hint: "Pin a thumbnail"),
        ToolDef(id: "copy", title: "Copy", symbol: "doc.on.doc", hint: "Duplicate beside the original"),
        ToolDef(id: "move", title: "Move", symbol: "folder", hint: "Move to a folder"),
        ToolDef(id: "copyPath", title: "Copy Path", symbol: "link", hint: "Put the path on the clipboard"),
        ToolDef(id: "terminal", title: "Terminal", symbol: "terminal", hint: "Open here"),
        ToolDef(id: "reveal", title: "Reveal", symbol: "magnifyingglass", hint: "Show in Finder")
    ]

    // MARK: Choices

    static func choices(for urls: [URL], mode: WheelMode) -> [WheelChoice] {
        let own = rawChoices(for: urls, mode: mode)
        return own.isEmpty ? actionChoices() : own
    }

    /// The choices for one surface without the actions fallback. The wheel
    /// draws every non-empty surface at once, so a fallback would duplicate
    /// the actions ring.
    static func rawChoices(for urls: [URL], mode: WheelMode) -> [WheelChoice] {
        switch mode {
        case .convert:
            return availableFormats(for: urls).map { fmt in
                WheelChoice(id: "fmt-\(fmt.ext)", title: fmt.title,
                            symbol: fmt.symbol, hint: "Convert to \(fmt.title)",
                            payload: .format(fmt))
            }
        case .tools:
            guard let kind = KindDetector.commonKind(urls) else { return [] }
            return tools(for: kind).map { tool in
                WheelChoice(id: "tool-\(tool.id)", title: tool.title,
                            symbol: tool.symbol, hint: tool.hint,
                            payload: .tool(tool.id))
            }
        case .actions:
            return actionChoices()
        }
    }

    /// Every surface that can act on the drop, outermost ring first.
    static func surfaces(for urls: [URL]) -> [(mode: WheelMode, choices: [WheelChoice])] {
        let built = [WheelMode.convert, .tools, .actions]
            .map { (mode: $0, choices: rawChoices(for: urls, mode: $0)) }
            .filter { !$0.choices.isEmpty }
        if built.isEmpty { return [(mode: .actions, choices: actionChoices())] }
        return built
    }

    static func actionChoices() -> [WheelChoice] {
        actions.map { action in
            WheelChoice(id: "action-\(action.id)", title: action.title,
                        symbol: action.symbol, hint: action.hint,
                        payload: .action(action.id))
        }
    }

    // MARK: Stats

    static var optionCount: Int {
        let inputs: [(Kind, Int)] = [
            (.image, KindDetector.imageIn.count),
            (.video, KindDetector.videoIn.count),
            (.audio, KindDetector.audioIn.count),
            (.pdf, 1),
            (.document, KindDetector.docIn.count),
            (.slides, KindDetector.slidesIn.count),
            (.sheet, KindDetector.sheetIn.count),
            (.subtitle, KindDetector.subIn.count),
            (.archive, KindDetector.archiveIn.count)
        ]
        return inputs.reduce(0) { sum, pair in
            sum + pair.1 * formats(for: pair.0).count
        }
    }

    static var toolCount: Int {
        let kinds: [Kind] = [.image, .video, .audio, .pdf, .document, .slides, .sheet, .subtitle, .archive]
        return kinds.reduce(0) { $0 + tools(for: $1).count }
    }
}
