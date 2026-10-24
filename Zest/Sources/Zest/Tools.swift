import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tool runner

enum ToolRunner {
    static func isBatch(_ id: String) -> Bool {
        ["join", "merge", "collage"].contains(id)
    }

    static func run(tool: String, inputs: [URL], params: [String: String]) throws -> [URL] {
        guard let first = inputs.first else { return [] }
        let kind = KindDetector.kind(of: first)

        switch kind {
        case .image:
            return try runImage(tool: tool, inputs: inputs, params: params)
        case .video, .audio:
            return try runMedia(tool: tool, inputs: inputs, params: params)
        case .pdf:
            return try runPDF(tool: tool, inputs: inputs, params: params)
        case .document, .slides, .sheet:
            return try runOffice(tool: tool, inputs: inputs, params: params)
        case .subtitle:
            return try runSubtitle(tool: tool, inputs: inputs, params: params)
        case .archive:
            return try runArchive(tool: tool, inputs: inputs, params: params)
        default:
            throw ZestError("No tools for .\(first.pathExtension) files")
        }
    }

    // MARK: Images

    private static func runImage(tool: String, inputs: [URL],
                                 params: [String: String]) throws -> [URL] {
        let input = inputs[0]
        switch tool {
        case "compress", "targetSize":
            return try compressImage(input, params: params)
        case "resize":
            let width = Int(params["width"] ?? "") ?? 0
            let height = Int(params["height"] ?? "") ?? 0
            guard width > 0 || height > 0 else { throw ZestError("Enter a width or height") }
            let image = try ImageOps.apply(try ImageEngine.load(input), params: [
                "width": "\(width)", "height": "\(height)", "fit": params["fit"] ?? "fit"
            ])
            return [try write(image, input: input, suffix: "resized", ext: params["format"])]
        case "crop":
            guard let crop = params["crop"], !crop.isEmpty else { throw ZestError("No crop area") }
            let image = try ImageOps.apply(try ImageEngine.load(input), params: ["crop": crop])
            return [try write(image, input: input, suffix: "cropped", ext: params["format"])]
        case "frame":
            let image = ImageOps.addBackground(try ImageEngine.load(input), params: params)
            return [try write(image, input: input, suffix: "framed",
                              ext: params["format"] ?? "png")]
        case "rotate":
            let degrees = Double(params["degrees"] ?? "90") ?? 90
            let image = try ImageOps.apply(try ImageEngine.load(input), params: ["rotate": "\(degrees)"])
            return [try write(image, input: input, suffix: "rotated", ext: params["format"])]
        case "flip":
            let image = try ImageOps.apply(try ImageEngine.load(input),
                                           params: ["flip": params["direction"] ?? "horizontal"])
            return [try write(image, input: input, suffix: "flipped", ext: params["format"])]
        case "adjust":
            let image = try ImageOps.apply(try ImageEngine.load(input), params: [
                "brightness": params["brightness"] ?? "0",
                "contrast": params["contrast"] ?? "1",
                "saturation": params["saturation"] ?? "1"
            ])
            return [try write(image, input: input, suffix: "adjusted", ext: params["format"])]
        case "grayscale":
            let image = try ImageOps.apply(try ImageEngine.load(input), params: ["grayscale": "1"])
            return [try write(image, input: input, suffix: "bw", ext: params["format"])]
        case "annotate":
            guard let markup = params["markup"] else { throw ZestError("No markup") }
            let image = try ImageOps.apply(try ImageEngine.load(input), params: ["markup": markup])
            return [try write(image, input: input, suffix: "annotated", ext: params["format"])]
        case "redact":
            guard let markup = params["markup"] else { throw ZestError("No redactions") }
            let image = try ImageOps.apply(try ImageEngine.load(input), params: ["markup": markup])
            return [try write(image, input: input, suffix: "redacted", ext: params["format"])]
        case "metadata":
            if params["remove"] == "1" {
                return [try write(try ImageEngine.load(input), input: input, suffix: "clean",
                                  ext: input.pathExtension, strip: true)]
            }
            let values = decodeValues(params["values"])
            return try applyImageMetadata(input, values: values)
        case "strip":
            let ext = input.pathExtension.lowercased()
            if ext == "pdf" { return try PDFEngine.applyMetadata(input, values: [:], remove: true) }
            let image = try ImageEngine.load(input)
            let out = Naming.output(for: input, ext: ext, suffix: "clean")
            try ImageEngine.encode(image, to: out, ext: ext, quality: 0.92)
            return [out]
        case "collage":
            return try collage(inputs, params: params)
        case "qr":
            let image = try ImageEngine.load(input)
            let codes = VisionQR.detect(image)
            showQR(codes, title: input.lastPathComponent)
            return []
        default:
            throw ZestError("Unknown image tool \(tool)")
        }
    }

    static func write(_ image: CGImage, input: URL, suffix: String,
                      ext: String?, strip: Bool = false) throws -> URL {
        let target = (ext?.isEmpty == false ? ext! : input.pathExtension).lowercased()
        let out = Naming.output(for: input, ext: target, suffix: suffix)
        try ImageEngine.encode(image, to: out, ext: target, quality: 0.9)
        return out
    }

    static func compressImage(_ input: URL, params: [String: String]) throws -> [URL] {
        let image = try ImageEngine.load(input)
        let ext = input.pathExtension.lowercased()
        let quality = Double(params["quality"] ?? "") ?? ImageEngine.defaultQuality(for: ext)
        let maxDim = Int(params["maxDimension"] ?? "") ?? 0
        let percent = Double(params["percent"] ?? "") ?? 0
        let target = Bytes.parse(params["target"] ?? "")
            ?? (percent > 0 ? Int64(Double(input.fileSize) * (1 - percent / 100)) : nil)

        var working = image
        if maxDim > 0, max(working.width, working.height) > maxDim {
            working = ImageOps.resize(working, width: maxDim, height: 0, fit: "fit")
        }

        let out = Naming.output(for: input, ext: ext, suffix: "compressed")

        guard let target, target > 0 else {
            try ImageEngine.encode(working, to: out, ext: ext, quality: quality)
            return [out]
        }

        if ext == "png" {
            var candidate = working
            var data = ImageEngine.encodeData(candidate, ext: "png", quality: 1)
            let scale = 0.9
            while (data?.count ?? Int.max) > target, candidate.width > 64, scale > 0.2 {
                candidate = ImageOps.resize(candidate, width: Int(Double(candidate.width) * scale),
                                            height: Int(Double(candidate.height) * scale), fit: "stretch")
                data = ImageEngine.encodeData(candidate, ext: "png", quality: 1)
            }
            guard let data else { throw ZestError("Couldn't compress image") }
            try data.write(to: out)
            return [out]
        }

        var low = 0.15
        var high = 0.95
        var best: Data?
        var candidate = working
        var attempts = 0

        while attempts < 12 && low <= high {
            let mid = (low + high) / 2
            let data = ImageEngine.encodeData(candidate, ext: ext, quality: mid)
            if let data {
                if data.count <= Int(target) {
                    best = data
                    low = mid + 0.04
                } else {
                    high = mid - 0.04
                }
            } else {
                break
            }
            attempts += 1
        }

        if best == nil, ext != "png" {
            // Nothing fit at full size: shrink and try again.
            for scale in stride(from: 0.85, through: 0.35, by: -0.1) {
                candidate = ImageOps.resize(working,
                                            width: Int(Double(working.width) * scale),
                                            height: Int(Double(working.height) * scale),
                                            fit: "stretch")
                let data = ImageEngine.encodeData(candidate, ext: ext, quality: 0.55)
                if let data, data.count <= Int(target) { best = data; break }
            }
        }

        guard let best else { throw ZestError("Couldn't reach \(Bytes.format(target)) without destroying the image") }
        try best.write(to: out)
        return [out]
    }

    // MARK: Image metadata

    static func imageMetadata(_ url: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [] }
        var out: [(String, String)] = [("File size", Bytes.format(url.fileSize))]
        func add(_ dict: [CFString: Any], prefix: String) {
            for (key, value) in dict where !(value is [CFString: Any]) && !(value is [Any]) {
                let label = prefix + readableKey(key as String)
                let text = "\(value)"
                if !text.isEmpty { out.append((label, text)) }
            }
        }
        add(props, prefix: "")
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            add(tiff, prefix: "TIFF · ")
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            add(exif, prefix: "EXIF · ")
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            add(gps, prefix: "GPS · ")
        }
        if let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            add(iptc, prefix: "IPTC · ")
        }
        return out
    }

    private static func readableKey(_ key: String) -> String {
        var out = ""
        for ch in key {
            if ch.isUppercase, !out.isEmpty { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    static func applyImageMetadata(_ input: URL, values: [String: String]) throws -> [URL] {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ZestError("Can't read metadata") }
        let image = try ImageEngine.load(input)
        let ext = input.pathExtension.lowercased()

        var props: [CFString: Any] = original
        props[kCGImagePropertyOrientation] = 1
        props[kCGImagePropertyPixelWidth] = nil
        props[kCGImagePropertyPixelHeight] = nil

        var tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        var exif = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        var iptc = (props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]

        if let title = values["Title"], !title.isEmpty {
            tiff[kCGImagePropertyTIFFImageDescription] = title
            iptc[kCGImagePropertyIPTCCaptionAbstract] = title
        }
        if let author = values["Author"], !author.isEmpty {
            tiff[kCGImagePropertyTIFFArtist] = author
            iptc[kCGImagePropertyIPTCByline] = author
        }
        if let copyright = values["Copyright"], !copyright.isEmpty {
            tiff[kCGImagePropertyTIFFCopyright] = copyright
            iptc[kCGImagePropertyIPTCCopyrightNotice] = copyright
        }
        if let keywords = values["Keywords"], !keywords.isEmpty {
            iptc[kCGImagePropertyIPTCKeywords] = keywords.components(separatedBy: ",")
                .map { $0.trimmed() }
        }
        if let description = values["Description"], !description.isEmpty {
            exif[kCGImagePropertyExifUserComment] = description
        }
        props[kCGImagePropertyTIFFDictionary] = tiff
        props[kCGImagePropertyExifDictionary] = exif
        props[kCGImagePropertyIPTCDictionary] = iptc

        let out = Naming.output(for: input, ext: ext, suffix: "metadata")
        try ImageEngine.encode(image, to: out, ext: ext, quality: 0.92, properties: props)
        return [out]
    }

    // MARK: Media

    private static func runMedia(tool: String, inputs: [URL],
                                 params: [String: String]) throws -> [URL] {
        let input = inputs[0]
        let ext = input.pathExtension.lowercased()
        let info = MediaProbe.info(input)

        switch tool {
        case "compress":
            let out = Naming.output(for: input, ext: ext, suffix: "compressed")
            let percent = Double(params["percent"] ?? "")
            let target = Bytes.parse(params["target"] ?? "")
            try MediaEngine.compress(input, targetBytes: target, percent: percent, to: out)
            return [out]
        case "targetSize":
            guard let target = Bytes.parse(params["target"] ?? "") else {
                throw ZestError("Enter a target size, like 8MB")
            }
            let out = Naming.output(for: input, ext: ext, suffix: "compressed")
            try MediaEngine.compress(input, targetBytes: target, percent: nil, to: out)
            return [out]
        case "trim":
            let start = Double(params["start"] ?? "0") ?? 0
            let end = Double(params["end"] ?? "") ?? info.duration
            let out = Naming.output(for: input, ext: ext, suffix: "trimmed")
            try MediaEngine.trim(input, start: start, end: end, to: out)
            return [out]
        case "split":
            let out = Naming.output(for: input, ext: ext, suffix: "part")
            return try MediaEngine.split(input,
                                         parts: Int(params["parts"] ?? ""),
                                         every: Double(params["every"] ?? ""),
                                         to: out)
        case "join":
            let out = Naming.batchOutput(for: inputs, ext: ext, suffix: "joined")
            return try MediaEngine.join(inputs, to: out)
        case "speed":
            let factor = Double(params["factor"] ?? "1.5") ?? 1.5
            let out = Naming.output(for: input, ext: ext, suffix: "speed")
            try MediaEngine.speed(input, factor: factor, to: out)
            return [out]
        case "crop":
            let w = Int(params["width"] ?? "") ?? info.width
            let h = Int(params["height"] ?? "") ?? info.height
            let x = Int(params["x"] ?? "0") ?? 0
            let y = Int(params["y"] ?? "0") ?? 0
            let out = Naming.output(for: input, ext: ext, suffix: "cropped")
            try MediaEngine.crop(input, width: w, height: h, x: x, y: y, to: out)
            return [out]
        case "rotate":
            let degrees = Int(params["degrees"] ?? "90") ?? 90
            let out = Naming.output(for: input, ext: ext, suffix: "rotated")
            try MediaEngine.rotate(input, degrees: degrees, to: out)
            return [out]
        case "snapshot":
            let time = Double(params["time"] ?? "0") ?? 0
            let out = Naming.output(for: input, ext: params["format"] ?? "png", suffix: "frame")
            try MediaEngine.snapshot(input, at: time, to: out)
            return [out]
        case "snapshots":
            let format = (params["format"] ?? "png").lowercased()
            var times = (params["times"] ?? "")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .compactMap { Double($0) }
                .filter { $0 >= 0 }
            if times.isEmpty {
                let count = max(1, min(30, Int(params["count"] ?? "") ?? 6))
                if count == 1 {
                    times = [0]
                } else if info.duration > 0 {
                    times = (0..<count).map { Double($0) / Double(count - 1) * info.duration }
                } else {
                    times = (0..<count).map(Double.init)
                }
            }
            return try times.enumerated().map { index, time in
                let out = Naming.output(for: input, ext: format,
                                        suffix: String(format: "frame-%02d", index + 1))
                try MediaEngine.snapshot(input, at: time, to: out)
                return out
            }
        case "gif":
            let out = Naming.output(for: input, ext: "gif", suffix: "loop")
            _ = try MediaEngine.makeGIF(input, to: out,
                                        fps: Int(params["fps"] ?? "12") ?? 12,
                                        width: Int(params["width"] ?? "720") ?? 720)
            return [out]
        case "mute":
            let out = Naming.output(for: input, ext: ext, suffix: "muted")
            try MediaEngine.mute(input, to: out)
            return [out]
        case "extractAudio":
            let target = params["format"] ?? "mp3"
            let out = Naming.output(for: input, ext: target, suffix: "audio")
            try MediaEngine.extractAudio(input, to: out, ext: target)
            return [out]
        case "normalize":
            let lufs = Double(params["lufs"] ?? "-16") ?? -16
            let out = Naming.output(for: input, ext: ext, suffix: "normalized")
            try MediaEngine.normalize(input, lufs: lufs, to: out)
            return [out]
        case "bleep":
            let start = Double(params["start"] ?? "0") ?? 0
            let end = Double(params["end"] ?? "1") ?? 1
            let out = Naming.output(for: input, ext: ext, suffix: "bleeped")
            try MediaEngine.bleep(input, start: start, end: end, to: out)
            return [out]
        case "redactVideo":
            let rect = CGRect(x: Double(params["x"] ?? "0") ?? 0,
                              y: Double(params["y"] ?? "0") ?? 0,
                              width: Double(params["w"] ?? "") ?? Double(info.width) / 2,
                              height: Double(params["h"] ?? "") ?? Double(info.height) / 2)
            guard rect.width >= 2, rect.height >= 2 else {
                throw ZestError("Select a region to redact")
            }
            let start = Double(params["start"] ?? "0") ?? 0
            let end = Double(params["end"] ?? "") ?? info.duration
            let out = Naming.output(for: input, ext: "mp4", suffix: "redacted")
            try MediaEngine.redactVideo(input, region: rect, start: start, end: end,
                                        mode: params["mode"] ?? "blur",
                                        crf: MediaEngine.crfForPreset(), to: out)
            return [out]
        case "redactAudio":
            let start = Double(params["start"] ?? "0") ?? 0
            let end = Double(params["end"] ?? "1") ?? 1
            let out = Naming.output(for: input, ext: ext, suffix: "redacted")
            try MediaEngine.redactAudio(input, start: start, end: end,
                                        mode: params["mode"] ?? "tone",
                                        frequency: Double(params["frequency"] ?? "1000") ?? 1000,
                                        duration: info.duration,
                                        keepVideo: info.hasVideo, to: out)
            return [out]
        case "audioToVideo":
            let background = params["background"].flatMap { path -> URL? in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil
                    : URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            }
            let width = Int(params["width"] ?? "") ?? 1920
            let height = Int(params["height"] ?? "") ?? 1080
            let out = Naming.output(for: input, ext: "mp4", suffix: "video")
            try MediaEngine.audioToVideo(input, background: background,
                                         color: params["color"] ?? "#1C1C1E",
                                         width: width, height: height,
                                         crf: MediaEngine.crfForPreset(), to: out)
            return [out]
        case "channels":
            let mono = (params["mode"] ?? "mono") == "mono"
            let out = Naming.output(for: input, ext: ext, suffix: mono ? "mono" : "stereo")
            try MediaEngine.channels(input, mono: mono, to: out)
            return [out]
        case "sampleRate":
            let rate = Int(params["rate"] ?? "44100") ?? 44100
            let out = Naming.output(for: input, ext: ext, suffix: "resampled")
            try MediaEngine.sampleRate(input, rate: rate, to: out)
            return [out]
        case "metadata":
            if params["remove"] == "1" {
                guard let ffmpeg = ToolFinder.ffmpeg else {
                    throw ZestError("ffmpeg is required for media metadata")
                }
                let out = Naming.output(for: input, ext: ext, suffix: "clean")
                var args = ["-y", "-i", input.path, "-map", "0", "-c", "copy",
                            "-map_metadata", "-1", out.path]
                if ext == "mp4" || ext == "mov" { args = ["-y", "-i", input.path, "-map_metadata", "-1",
                                                          "-c", "copy", "-movflags", "+faststart", out.path] }
                try Shell.run(ffmpeg, args)
                return [out]
            }
            let values = decodeValues(params["values"])
            let out = Naming.output(for: input, ext: ext, suffix: "metadata")
            try MediaEngine.applyMetadata(input, values: values, remove: false, to: out)
            return [out]
        case "strip":
            let out = Naming.output(for: input, ext: ext, suffix: "clean")
            try MediaEngine.applyMetadata(input, values: [:], remove: true, to: out)
            return [out]
        default:
            throw ZestError("Unknown media tool \(tool)")
        }
    }

    // MARK: PDF

    private static func runPDF(tool: String, inputs: [URL],
                               params: [String: String]) throws -> [URL] {
        let input = inputs[0]
        switch tool {
        case "compress":
            let out = Naming.output(for: input, ext: "pdf", suffix: "compressed")
            let percent = Double(params["percent"] ?? "") ?? 0
            let target = Bytes.parse(params["target"] ?? "")
                ?? (percent > 0 ? Int64(Double(input.fileSize) * (1 - percent / 100)) : nil)
            try PDFEngine.compress(input, targetBytes: target, to: out)
            return [out]
        case "targetSize":
            guard let target = Bytes.parse(params["target"] ?? "") else {
                throw ZestError("Enter a target size")
            }
            let out = Naming.output(for: input, ext: "pdf", suffix: "compressed")
            try PDFEngine.compress(input, targetBytes: target, to: out)
            return [out]
        case "merge":
            let out = Naming.batchOutput(for: inputs, ext: "pdf", suffix: "merged")
            try PDFEngine.merge(inputs, to: out)
            return [out]
        case "split":
            return try PDFEngine.split(input, ranges: params["ranges"] ?? "")
        case "reorder":
            return try PDFEngine.reorder(input, spec: params["order"] ?? "")
        case "rotate":
            return try PDFEngine.rotate(input, degrees: Int(params["degrees"] ?? "90") ?? 90,
                                        pages: params["pages"] ?? "")
        case "extractImages":
            return try PDFEngine.extractImages(input,
                                               dpi: Double(params["dpi"] ?? "300") ?? 300,
                                               ext: params["format"] ?? "png")
        case "metadata":
            if params["remove"] == "1" {
                return try PDFEngine.applyMetadata(input, values: [:], remove: true)
            }
            let values = decodeValues(params["values"])
            return try PDFEngine.applyMetadata(input, values: values, remove: false)
        case "strip":
            return try PDFEngine.applyMetadata(input, values: [:], remove: true)
        case "qr":
            showQR(PDFEngine.qrCodes(input), title: input.lastPathComponent)
            return []
        default:
            throw ZestError("Unknown PDF tool \(tool)")
        }
    }

    // MARK: Office

    private static func runOffice(tool: String, inputs: [URL],
                                  params: [String: String]) throws -> [URL] {
        let input = inputs[0]
        switch tool {
        case "metadata":
            if params["remove"] == "1" {
                return try stripOffice(input)
            }
            return []
        case "strip":
            return try stripOffice(input)
        default:
            throw ZestError("Unknown document tool \(tool)")
        }
    }

    static func officeMetadata(_ url: URL) -> [(String, String)] {
        let ext = url.pathExtension.lowercased()
        guard ["docx", "xlsx", "pptx", "pages"].contains(ext) else {
            return [("File size", Bytes.format(url.fileSize))]
        }
        let dir = Temp.dir()
        guard (try? ZipUtil.unzip(url, to: dir)) != nil else { return [] }
        var out: [(String, String)] = [("File size", Bytes.format(url.fileSize))]
        for name in ["docProps/core.xml", "docProps/app.xml"] {
            guard let xml = try? String(contentsOf: dir.appendingPathComponent(name),
                                        encoding: .utf8) else { continue }
            for tag in ["dc:title", "dc:creator", "dc:subject", "dc:description",
                        "cp:keywords", "cp:lastModifiedBy", "dcterms:created",
                        "dcterms:modified", "Application", "Pages", "Words"] {
                if let value = firstTag(tag, in: xml), !value.isEmpty {
                    out.append((tag.split(separator: ":").last.map(String.init) ?? tag, value))
                }
            }
        }
        return out
    }

    static func stripOffice(_ input: URL) throws -> [URL] {
        let dir = Temp.dir()
        try ZipUtil.unzip(input, to: dir)
        let props = dir.appendingPathComponent("docProps", isDirectory: true)
        try? FileManager.default.removeItem(at: props)

        let rels = dir.appendingPathComponent("_rels/.rels")
        if let xml = try? String(contentsOf: rels, encoding: .utf8) {
            let cleaned = xml.replacingOccurrences(
                of: "<Relationship[^>]*docProps[^>]*/>", with: "",
                options: .regularExpression)
            try? cleaned.write(to: rels, atomically: true, encoding: .utf8)
        }
        let types = dir.appendingPathComponent("[Content_Types].xml")
        if let xml = try? String(contentsOf: types, encoding: .utf8) {
            let cleaned = xml.replacingOccurrences(
                of: "<Override[^>]*docProps[^>]*/>", with: "",
                options: .regularExpression)
            try? cleaned.write(to: types, atomically: true, encoding: .utf8)
        }
        let out = Naming.output(for: input, ext: input.pathExtension, suffix: "clean")
        try ZipUtil.zipDirectory(dir, to: out)
        return [out]
    }

    private static func firstTag(_ tag: String, in xml: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return TextTools.unescapeXML(ns.substring(with: match.range(at: 1)))
    }

    // MARK: Archives

    private static func runArchive(tool: String, inputs: [URL],
                                   params: [String: String]) throws -> [URL] {
        let input = inputs[0]
        switch tool {
        case "extract":
            return [try ArchiveEngine.extract(input)]
        default:
            throw ZestError("Unknown archive tool \(tool)")
        }
    }

    // MARK: Subtitles

    private static func runSubtitle(tool: String, inputs: [URL],
                                    params: [String: String]) throws -> [URL] {
        let input = inputs[0]
        switch tool {
        case "shift":
            let seconds = Double(params["seconds"] ?? "0") ?? 0
            return try SubtitleEngine.shift(input, seconds: seconds)
        case "merge":
            let out = Naming.batchOutput(for: inputs, ext: "srt", suffix: "merged")
            try SubtitleEngine.merge(inputs, to: out)
            return [out]
        default:
            throw ZestError("Unknown subtitle tool \(tool)")
        }
    }

    // MARK: Collage

    static func collage(_ inputs: [URL], params: [String: String]) throws -> [URL] {
        let images = try inputs.map { try ImageEngine.load($0) }
        guard !images.isEmpty else { throw ZestError("No images") }
        let layout = params["layout"] ?? "grid"
        let spacing = max(0, Int(params["spacing"] ?? "16") ?? 16)
        let columns: Int
        switch layout {
        case "horizontal": columns = images.count
        case "vertical": columns = 1
        default: columns = max(1, Int(ceil(sqrt(Double(images.count)))))
        }
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let cellW = images.map(\.width).max() ?? 800
        let cellH = images.map(\.height).max() ?? 600
        let width = columns * cellW + (columns + 1) * spacing
        let height = rows * cellH + (rows + 1) * spacing

        let bg = NSColor(hex: params["background"] ?? "#FFFFFF") ?? .white
        guard let composite = ImageOps.canvas(width: width, height: height, draw: { ctx in
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (index, image) in images.enumerated() {
                let col = index % columns
                let row = index / columns
                let cellX = CGFloat(spacing + col * (cellW + spacing))
                let cellY = CGFloat(height - (spacing + (row + 1) * cellH + row * spacing))
                let scale = min(Double(cellW) / Double(image.width),
                                Double(cellH) / Double(image.height))
                let w = CGFloat(Double(image.width) * scale)
                let h = CGFloat(Double(image.height) * scale)
                ctx.draw(image, in: CGRect(x: cellX + (CGFloat(cellW) - w) / 2,
                                           y: cellY + (CGFloat(cellH) - h) / 2,
                                           width: w, height: h))
            }
        }) else { throw ZestError("Couldn't build collage") }

        let ext = (params["format"] ?? "jpg").lowercased()
        if ext == "pdf" {
            let out = Naming.batchOutput(for: inputs, ext: "pdf", suffix: "collage")
            try PDFEngine.buildPDF(images: [composite], to: out)
            return [out]
        }
        let out = Naming.batchOutput(for: inputs, ext: ext, suffix: "collage")
        try ImageEngine.encode(composite, to: out, ext: ext, quality: 0.92)
        return [out]
    }

    // MARK: Helpers

    static func showQR(_ codes: [String], title: String) {
        onMain {
            ToolUI.showQR(codes, title: title)
        }
    }

    static func decodeValues(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return values
    }

    static func encodeValues(_ values: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

// MARK: - NSColor hex

extension NSColor {
    convenience init?(hex: String) {
        var text = hex.trimmed().replacingOccurrences(of: "#", with: "")
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
