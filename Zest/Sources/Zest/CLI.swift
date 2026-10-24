import AppKit
import PDFKit
import CoreText

// MARK: - Headless entry points

enum CLI {
    static func run(_ args: [String]) -> Int32 {
        // AppKit rendering (fonts, NSImage, demo assets) needs an application
        // instance, but the CLI never enters the run loop.
        _ = NSApplication.shared

        guard let command = args.first else {
            usage()
            return 2
        }
        let rest = Array(args.dropFirst())
        switch command {
        case "formats":
            return formats(rest)
        case "convert":
            return convert(rest)
        case "tool":
            return tool(rest)
        case "selftest":
            return selftest()
        case "uitest":
            return UITest.run()
        case "wheel":
            return wheelSnapshot(rest)
        case "settings-preview":
            return settingsPreview(rest)
        case "help", "-h", "--help":
            usage()
            return 0
        default:
            err("Unknown command: \(command)")
            usage()
            return 2
        }
    }

    // MARK: formats

    private static func formats(_ args: [String]) -> Int32 {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard !paths.isEmpty else {
            err("Usage: Zest formats <file>...")
            return 2
        }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                err("Missing: \(path)")
                return 1
            }
            let kind = KindDetector.kind(of: url)
            out("\(url.lastPathComponent) — \(kind.title)")
            let formats = Catalog.availableFormats(for: [url])
            if formats.isEmpty {
                out("  (no output formats)")
            }
            for fmt in formats {
                let ext = fmt.ext.padding(toLength: 7, withPad: " ", startingAt: 0)
                out("  \(ext) \(fmt.title)")
            }
        }
        return 0
    }

    // MARK: settings preview

    /// Development-only preview of the settings layout. Renders one tab
    /// offscreen so no screen-recording grant is needed.
    /// Usage: `Zest settings-preview <tab 0-4> <out.png>`.
    private static func settingsPreview(_ args: [String]) -> Int32 {
        guard args.count >= 2 else {
            err("Usage: Zest settings-preview <tab 0-4> <out.png>")
            return 2
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let controller = SettingsWindow()
        controller.showTabForPreview(Int(args[0]) ?? 0)
        guard controller.snapshotForPreview(to: URL(fileURLWithPath: args[1])) else {
            err("Couldn't render the settings preview")
            return 1
        }
        out(URL(fileURLWithPath: args[1]).path)
        return 0
    }

    // MARK: wheel snapshot

    /// Renders the wheel offscreen to PNG. Screen Recording is denied on this
    /// bench, so this is the only way to inspect the drawing and verify that
    /// every slice and label is on screen after a UI change.
    private static func wheelSnapshot(_ args: [String]) -> Int32 {
        var output: String?
        var kind: Kind = .image
        var hover: Int?
        var mode: WheelMode = .convert
        var style: WheelStyle = Prefs.wheelStyle
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--kind":
                guard index + 1 < args.count, let parsed = Kind(rawValue: args[index + 1]) else {
                    err("Usage: Zest wheel <out.png> [--kind image|video|audio|pdf|document|slides|sheet|subtitle|archive|folder] [--style fan|rings] [--mode convert|tools|actions] [--hover N]")
                    return 2
                }
                kind = parsed
                index += 2
            case "--hover":
                guard index + 1 < args.count, let n = Int(args[index + 1]) else {
                    err("--hover needs an index")
                    return 2
                }
                hover = n
                index += 2
            case "--mode":
                guard index + 1 < args.count, let parsed = WheelMode(rawValue: args[index + 1]) else {
                    err("--mode needs convert, tools, or actions")
                    return 2
                }
                mode = parsed
                index += 2
            case "--style":
                guard index + 1 < args.count, let parsed = WheelStyle(rawValue: args[index + 1]) else {
                    err("--style needs fan or rings")
                    return 2
                }
                style = parsed
                index += 2
            default:
                if arg.hasPrefix("-") {
                    err("Unknown option: \(arg)")
                    return 2
                }
                output = arg
                index += 1
            }
        }
        guard let output else {
            err("Usage: Zest wheel <out.png> [--kind …] [--style fan|rings] [--mode …] [--hover N]")
            return 2
        }

        let url = URL(fileURLWithPath: output)
        let snapshotURL = sampleURL(for: kind)
        let side: CGFloat = 1000
        let view = WheelView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.style = style
        view.surfaces = Catalog.surfaces(for: [snapshotURL])
        view.emphasize(mode)
        view.center = NSPoint(x: side / 2, y: side / 2)
        view.count = 1
        view.kind = kind
        view.fileName = snapshotURL.lastPathComponent
        view.fileFormat = snapshotURL.pathExtension.isEmpty
            ? kind.title.uppercased()
            : snapshotURL.pathExtension.uppercased()
        view.totalBytes = snapshotURL.fileSize
        if let hover, hover >= 0 {
            var remaining = hover
            for (ringIndex, ring) in view.rings.enumerated() {
                if remaining < ring.choices.count {
                    view.hovered = WheelHit(ring: ringIndex, index: remaining)
                    break
                }
                remaining -= ring.choices.count
            }
        }
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            err("Couldn't allocate a bitmap for the wheel")
            return 1
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            err("Couldn't encode the wheel snapshot")
            return 1
        }
        do {
            try png.write(to: url)
            out(url.path)
            return 0
        } catch {
            err("Couldn't write \(url.path): \(error.localizedDescription)")
            return 1
        }
    }

    private static func sampleURL(for kind: Kind) -> URL {
        let name: String
        switch kind {
        case .image: name = "sample.png"
        case .video: name = "sample.mp4"
        case .audio: name = "sample.mp3"
        case .pdf: name = "sample.pdf"
        case .document: name = "sample.docx"
        case .slides: name = "sample.pptx"
        case .sheet: name = "sample.xlsx"
        case .subtitle: name = "sample.srt"
        case .archive: name = "sample.zip"
        case .folder:
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("zest-snapshot-folder", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        case .other: name = "sample.xyz"
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    // MARK: convert

    private static func convert(_ args: [String]) -> Int32 {        var paths: [String] = []
        var to: String?
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--to", index + 1 < args.count {
                to = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--to=") {
                to = String(arg.dropFirst("--to=".count))
                index += 1
                continue
            }
            if arg.hasPrefix("-") {
                err("Unknown option: \(arg)")
                return 2
            }
            paths.append(arg)
            index += 1
        }
        guard let ext = to?.lowercased(), !ext.isEmpty, !paths.isEmpty else {
            err("Usage: Zest convert <file>... --to <ext>")
            return 2
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            err("Missing: \(url.path)")
            return 1
        }

        do {
            if urls.count > 1, ext == "pdf",
               urls.allSatisfy({ KindDetector.kind(of: $0) == .image }) {
                let outputs = try PDFEngine.fromImages(urls)
                outputs.forEach { out($0.path) }
                return 0
            }
            for url in urls {
                let kind = KindDetector.kind(of: url)
                guard let fmt = Catalog.formats(for: kind).first(where: { $0.ext == ext }) else {
                    err("\(kind.title) can't become .\(ext)")
                    return 1
                }
                // Headless output now honours the same per-format defaults a
                // drag uses (quality, size, metadata, bitrate/depth, layouts).
                var params = Prefs.conversionParams(for: fmt)
                let src = url.pathExtension.lowercased()
                if fmt.ext == "pdf" { params["pdfLayout"] = Prefs.pdfLayout(for: src) }
                if fmt.ext == "epub" { params["epubLayout"] = Prefs.epubLayout(for: src) }
                let outputs = try Convert.perform(url, to: fmt, params: params)
                outputs.forEach { out($0.path) }
            }
            return 0
        } catch {
            err(error.localizedDescription)
            return 1
        }
    }

    // MARK: tool

    private static func tool(_ args: [String]) -> Int32 {
        var id: String?
        var paths: [String] = []
        var params: [String: String] = [:]
        var parsingParams = false

        for arg in args {
            if arg == "--params" {
                parsingParams = true
                continue
            }
            if parsingParams, let equals = arg.firstIndex(of: "=") {
                let key = String(arg[..<equals])
                let value = String(arg[arg.index(after: equals)...])
                if !key.isEmpty { params[key] = value }
                continue
            }
            if arg.hasPrefix("-") { continue }
            if id == nil {
                id = arg
            } else {
                paths.append(arg)
            }
        }

        guard let id, !paths.isEmpty else {
            err("Usage: Zest tool <id> <file>... [--params key=value]")
            return 2
        }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            err("Missing: \(url.path)")
            return 1
        }

        let kind = KindDetector.kind(of: urls[0])

        // Tools that report values rather than files stay headless here.
        if id == "qr" {
            let codes: [String]
            if kind == .pdf {
                codes = PDFEngine.qrCodes(urls[0])
            } else if kind == .image, let image = try? ImageEngine.load(urls[0]) {
                codes = VisionQR.detect(image)
            } else {
                err("QR input must be an image or PDF")
                return 2
            }
            if codes.isEmpty {
                out("No codes found in \(urls[0].lastPathComponent)")
            } else {
                codes.forEach { out($0) }
            }
            return 0
        }

        do {
            var outputs: [URL] = []
            if ToolRunner.isBatch(id) {
                outputs = try ToolRunner.run(tool: id, inputs: urls, params: params)
            } else {
                for url in urls {
                    outputs += try ToolRunner.run(tool: id, inputs: [url], params: params)
                }
            }
            if outputs.isEmpty {
                out("No outputs")
            } else {
                outputs.forEach { out($0.path) }
            }
            return 0
        } catch {
            err(error.localizedDescription)
            return 1
        }
    }

    // MARK: selftest

    private static func selftest() -> Int32 {
        let root = Temp.dir(prefix: "zest-selftest")
        out("Zest selftest — \(root.path)")

        do {
            let samples = try makeSamples(in: root)
            var harness = Harness()
            runTests(samples: samples, root: root, harness: &harness)
            out("")
            out("\(harness.pass) passed · \(harness.fail) failed · \(harness.skip) skipped")
            if harness.fail > 0 {
                out("Log: \(Log.url.path)")
                return 1
            }
            out("All checks passed.")
            return 0
        } catch {
            err("Selftest setup failed: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: Samples

    private struct Samples {
        let png: URL
        let png2: URL
        let pdf: URL
        let pdf2: URL
        let imagePDF: URL
        let scannedPDF: URL
        let mixedPDF: URL
        let txt: URL
        let md: URL
        let docx: URL
        let xlsx: URL
        let csv: URL
        let srt: URL
        let srt2: URL
        let zip: URL
        let mp4: URL
        let mp42: URL
        let wav: URL
        let ffmpeg: Bool
    }

    private static func makeSamples(in root: URL) throws -> Samples {
        func at(_ name: String) -> URL { root.appendingPathComponent(name) }

        let png = at("sample.png")
        let png2 = at("sample2.png")
        guard let drawing = ImageOps.canvas(width: 640, height: 420, draw: { ctx in
            let orange = NSColor(calibratedRed: 0.96, green: 0.55, blue: 0.16, alpha: 1)
            ctx.setFillColor(orange.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 420))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: 70, y: 80, width: 220, height: 220))
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
            ctx.fill(CGRect(x: 360, y: 120, width: 190, height: 190))
        }) else { throw ZestError("Couldn't draw sample image") }
        try ImageEngine.encode(drawing, to: png, ext: "png", quality: 1)

        guard let drawing2 = ImageOps.canvas(width: 480, height: 360, draw: { ctx in
            ctx.setFillColor(NSColor.systemTeal.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 480, height: 360))
            ctx.setFillColor(NSColor.systemPink.cgColor)
            ctx.fillEllipse(in: CGRect(x: 120, y: 80, width: 240, height: 200))
        }) else { throw ZestError("Couldn't draw second sample image") }
        try ImageEngine.encode(drawing2, to: png2, ext: "png", quality: 1)

        let pdf = at("sample.pdf")
        try TextTools.pdf(from: """
        Zest selftest

        The quick brown fox jumps over the lazy dog.
        Second line for text extraction.
        Third line with numbers 12345.
        """, to: pdf)

        let pdf2 = at("sample2.pdf")
        try TextTools.pdf(from: "Second PDF\n\nAnother page of text.", to: pdf2)

        let imagePDF = at("image.pdf")
        try PDFEngine.buildPDF(images: [drawing], to: imagePDF)

        let scannedPDF = at("scanned.pdf")
        guard let scanned = ImageOps.canvas(width: 1400, height: 700, draw: { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 1400, height: 700))
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 160, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "ZEST OCR",
                attributes: [.font: font, .foregroundColor: NSColor.black]))
            ctx.textPosition = CGPoint(x: 120, y: 260)
            CTLineDraw(line, ctx)
        }) else { throw ZestError("Couldn't draw OCR sample") }
        try PDFEngine.buildPDF(images: [scanned], to: scannedPDF)

        let mixedPDF = at("mixed.pdf")
        try makeMixedPDF(mixedPDF)

        let txt = at("sample.txt")
        try "Zest selftest\nSecond line\nThird line\n".write(to: txt, atomically: true, encoding: .utf8)

        let md = at("sample.md")
        try "# Zest\n\nA **bold** line and a [link](https://example.com).\n\n- one\n- two\n"
            .write(to: md, atomically: true, encoding: .utf8)

        let docx = at("sample.docx")
        try DocxWriter.write(paragraphs: ["First paragraph.", "Second paragraph."],
                             title: "Zest Selftest", to: docx)

        let xlsx = at("sample.xlsx")
        try XlsxWriter.write(rows: [["Name", "Quantity"], ["Apple", "3"], ["Pear", "5"]],
                             sheetName: "Fruit", to: xlsx)

        let csv = at("sample.csv")
        try "Name,Quantity\r\nApple,3\r\nPear,5\r\n".write(to: csv, atomically: true, encoding: .utf8)

        let srt = at("sample.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,500
        Hello from Zest.

        2
        00:00:01,500 --> 00:00:03,000
        Second cue.

        """.write(to: srt, atomically: true, encoding: .utf8)

        let srt2 = at("sample2.srt")
        try """
        1
        00:00:03,000 --> 00:00:04,500
        Merged cue.

        """.write(to: srt2, atomically: true, encoding: .utf8)

        let zip = try ArchiveEngine.create(urls: [txt, csv], ext: "zip")

        let ffmpeg = ToolFinder.ffmpeg
        let mp4 = at("sample.mp4")
        let mp42 = at("sample2.mp4")
        let wav = at("sample.wav")
        if let ffmpeg {
            try Shell.run(ffmpeg, [
                "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=24:duration=1",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-shortest",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", mp4.path
            ])
            try FileManager.default.copyItem(at: mp4, to: mp42)
            try Shell.run(ffmpeg, [
                "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
                "-ac", "2", "-ar", "44100", wav.path
            ])
        }

        return Samples(png: png, png2: png2, pdf: pdf, pdf2: pdf2,
                       imagePDF: imagePDF, scannedPDF: scannedPDF, mixedPDF: mixedPDF,
                       txt: txt, md: md, docx: docx, xlsx: xlsx, csv: csv,
                       srt: srt, srt2: srt2, zip: zip,
                       mp4: mp4, mp42: mp42, wav: wav, ffmpeg: ffmpeg != nil)
    }

    private static func makeMixedPDF(_ url: URL) throws {
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &defaultBox, nil) else {
            throw ZestError("Couldn't create mixed-size PDF")
        }
        let boxes = [CGRect(x: 0, y: 0, width: 612, height: 792),
                     CGRect(x: 0, y: 0, width: 1000, height: 500)]
        for (index, box) in boxes.enumerated() {
            var media = box
            let info: [CFString: Any] = [
                kCGPDFContextMediaBox: Data(bytes: &media,
                                            count: MemoryLayout<CGRect>.size)
            ]
            ctx.beginPDFPage(info as CFDictionary)
            ctx.setFillColor((index == 0 ? NSColor.systemBlue : NSColor.systemGreen).cgColor)
            ctx.fill(box)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    // MARK: Tests

    private static func runTests(samples: Samples, root: URL, harness: inout Harness) {
        let png = samples.png
        let pdf = samples.pdf

        // Tool resolution must not trust a binary just because it exists.
        harness.check("Tool resolution skips broken binaries") {
            let dir = root.appendingPathComponent("toolcheck", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let broken = dir.appendingPathComponent("ffmpeg-broken")
            let good = dir.appendingPathComponent("ffmpeg-good")
            try "#!/bin/sh\nexit 133\n".write(to: broken, atomically: true, encoding: .utf8)
            try "#!/bin/sh\necho ffmpeg version test\nexit 0\n".write(to: good, atomically: true, encoding: .utf8)
            for path in [broken.path, good.path] {
                try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                      ofItemAtPath: path)
            }
            guard ToolFinder.resolve("ffmpeg", candidates: [broken.path, good.path]) == good.path else {
                throw ZestError("a broken binary shadowed the working one")
            }
            guard ToolFinder.resolve("ffmpeg", candidates: [broken.path]) == nil else {
                throw ZestError("a broken binary was accepted")
            }
            return [good]
        }

        // Image engine and image tools.
        harness.check("PNG → JPG") { try Convert.perform(png, to: format("jpg", for: .image)) }
        harness.check("Metadata carries natively across conversion") {
            // Tags survive a re-encode through ImageIO alone — no exiftool,
            // so preservation holds on any Mac a DMG lands on.
            let tagged = try ToolRunner.run(tool: "metadata", inputs: [png],
                                            params: ["values": #"{"Title":"Zest Meta","Author":"Bench"}"#])
            // Resize on the way through: stale pixel tags must not survive.
            var params = ["preserveMetadata": "1", "maxDimension": "800"]
            params["imageCompression"] = "balanced"
            let outs = try Convert.perform(tagged[0], to: format("jpg", for: .image),
                                           params: params)
            guard let src = CGImageSourceCreateWithURL(outs[0] as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
                      as? [CFString: Any],
                  let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] else {
                throw ZestError("converted jpg is unreadable")
            }
            guard tiff[kCGImagePropertyTIFFImageDescription] as? String == "Zest Meta",
                  tiff[kCGImagePropertyTIFFArtist] as? String == "Bench" else {
                throw ZestError("tags did not survive the conversion: \(tiff)")
            }
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let taggedW = exif[kCGImagePropertyExifPixelXDimension] as? Int,
               let taggedH = exif[kCGImagePropertyExifPixelYDimension] as? Int,
               let realW = props[kCGImagePropertyPixelWidth] as? Int,
               let realH = props[kCGImagePropertyPixelHeight] as? Int {
                guard realW <= 800 else { throw ZestError("resize was not applied") }
                guard taggedW == realW, taggedH == realH else {
                    throw ZestError("pixel tags describe \(taggedW)×\(taggedH) "
                                    + "but the image is \(realW)×\(realH)")
                }
            }
            return outs
        }
        harness.check("Strong image compression shrinks output") {
            let balanced = try Convert.perform(png, to: format("jpg", for: .image),
                                               params: ["quality": "0.9",
                                                        "imageCompression": "balanced"])
            let strong = try Convert.perform(png, to: format("jpg", for: .image),
                                             params: ["quality": "0.9",
                                                      "imageCompression": "strong"])
            guard strong[0].fileSize < balanced[0].fileSize else {
                throw ZestError("strong compression did not shrink the output")
            }
            return strong
        }
        if ToolFinder.cwebp != nil {
            harness.check("PNG → WebP") { try Convert.perform(png, to: format("webp", for: .image)) }
        } else {
            harness.skip += 1
            out("SKIP  PNG → WebP — cwebp is not installed")
        }
        harness.check("PNG → PDF") { try Convert.perform(png, to: format("pdf", for: .image)) }
        for fmt in Catalog.availableFormats(for: [png])
            where ["heic", "avif", "tiff", "bmp", "gif"].contains(fmt.ext) {
            harness.check("PNG → \(fmt.title)") {
                try Convert.perform(png, to: fmt)
            }
        }
        harness.check("Two images → one PDF") {
            try PDFEngine.fromImages([samples.png, samples.png2])
        }
        harness.check("Image resize") {
            try ToolRunner.run(tool: "resize", inputs: [png], params: ["width": "320"])
        }
        harness.check("Image crop") {
            try ToolRunner.run(tool: "crop", inputs: [png], params: ["crop": "0.1,0.1,0.5,0.5"])
        }
        harness.check("Image rotate") {
            try ToolRunner.run(tool: "rotate", inputs: [png], params: ["degrees": "90"])
        }
        harness.check("Image flip") {
            try ToolRunner.run(tool: "flip", inputs: [png], params: ["direction": "horizontal"])
        }
        harness.check("Image adjust") {
            try ToolRunner.run(tool: "adjust", inputs: [png], params: [
                "brightness": "0.05", "contrast": "1.1", "saturation": "1.05"
            ])
        }
        harness.check("Image grayscale") {
            try ToolRunner.run(tool: "grayscale", inputs: [png], params: [:])
        }
        harness.check("Image compress") {
            try ToolRunner.run(tool: "compress", inputs: [png], params: ["percent": "30"])
        }
        harness.check("Image annotate") {
            try ToolRunner.run(tool: "annotate", inputs: [png], params: [
                "markup": "{\"ops\":[{\"t\":\"rect\",\"rect\":[0.1,0.1,0.25,0.2],\"color\":[1,0,0,1],\"width\":0.004}]}"
            ])
        }
        harness.check("Image add background") {
            let outputs = try ToolRunner.run(tool: "frame", inputs: [png], params: [
                "padding": "12", "ratio": "square", "background": "#FFCC00",
                "radius": "8", "border": "4", "shadow": "soft", "format": "png"
            ])
            guard let out = outputs.first, let image = try? ImageEngine.load(out) else {
                throw ZestError("Add BG produced no readable image")
            }
            let source = try ImageEngine.load(png)
            guard image.width == image.height, image.width > source.width else {
                throw ZestError("Add BG did not produce a larger square canvas")
            }
            return outputs
        }
        harness.check("Image strip metadata") {
            try ToolRunner.run(tool: "strip", inputs: [png], params: [:])
        }
        harness.check("Image collage") {
            try ToolRunner.run(tool: "collage", inputs: [png, samples.png2],
                               params: ["layout": "grid", "format": "jpg"])
        }

        // PDF conversions.
        harness.check("PDF → JPG") {
            try PDFEngine.convert(pdf, to: format("jpg", for: .pdf), params: ["dpi": "72"])
        }
        harness.check("PDF → PNG") {
            try PDFEngine.convert(pdf, to: format("png", for: .pdf), params: ["dpi": "72"])
        }
        harness.check("PDF → TXT") { try Convert.perform(pdf, to: format("txt", for: .pdf)) }
        harness.check("PDF → Markdown") { try Convert.perform(pdf, to: format("md", for: .pdf)) }
        harness.check("PDF → DOCX") { try Convert.perform(pdf, to: format("docx", for: .pdf)) }
        harness.check("PDF → PPTX") { try Convert.perform(pdf, to: format("pptx", for: .pdf)) }
        harness.check("PDF → XLSX") { try Convert.perform(pdf, to: format("xlsx", for: .pdf)) }
        harness.check("PDF → EPUB") { try Convert.perform(pdf, to: format("epub", for: .pdf)) }
        harness.check("PDF → EPUB (fixed layout)") {
            let out = try Convert.perform(pdf, to: format("epub", for: .pdf),
                                          params: ["epubLayout": "fixed"])
            let listing = try Shell.run("/usr/bin/unzip", ["-l", out[0].path])
            guard listing.contains("images/page-1.jpg") else {
                throw ZestError("fixed layout has no page images")
            }
            let opf = try Shell.run("/usr/bin/unzip", ["-p", out[0].path, "OEBPS/content.opf"])
            guard opf.contains("pre-paginated") else {
                throw ZestError("fixed layout metadata is missing")
            }
            return out
        }
        harness.check("PDF → RTF") { try Convert.perform(pdf, to: format("rtf", for: .pdf)) }
        harness.check("Scanned PDF → TXT (OCR)") {
            let outputs = try Convert.perform(samples.scannedPDF, to: format("txt", for: .pdf))
            guard let first = outputs.first,
                  let text = try? String(contentsOf: first, encoding: .utf8),
                  text.uppercased().contains("ZEST") else {
                throw ZestError("OCR did not read the scanned page")
            }
            return outputs
        }

        // PDF tools.
        harness.check("PDF merge") {
            try ToolRunner.run(tool: "merge", inputs: [pdf, samples.pdf2], params: [:])
        }
        harness.check("PDF split") {
            try ToolRunner.run(tool: "split", inputs: [pdf], params: ["ranges": "1"])
        }
        harness.check("PDF split names pages from the source stem") {
            let outputs = try ToolRunner.run(tool: "split", inputs: [pdf], params: ["ranges": ""])
            guard let document = PDFDocument(url: pdf) else {
                throw ZestError("sample PDF is unreadable")
            }
            guard outputs.count == document.pageCount else {
                throw ZestError("split produced \(outputs.count) files for \(document.pageCount) pages")
            }
            let stem = pdf.deletingPathExtension().lastPathComponent
            for (index, output) in outputs.enumerated()
                where output.lastPathComponent != "\(stem)-page-\(index + 1).pdf" {
                throw ZestError("split wrote \(output.lastPathComponent), "
                    + "expected \(stem)-page-\(index + 1).pdf")
            }
            return outputs
        }
        harness.check("PDF reorder") {
            try ToolRunner.run(tool: "reorder", inputs: [pdf], params: ["order": "1"])
        }
        harness.check("PDF rotate") {
            try ToolRunner.run(tool: "rotate", inputs: [pdf], params: ["degrees": "90", "pages": "1"])
        }
        harness.check("PDF extract images") {
            try ToolRunner.run(tool: "extractImages", inputs: [pdf],
                               params: ["dpi": "72", "format": "png"])
        }
        harness.check("PDF extract embedded image at native size") {
            let outputs = try ToolRunner.run(tool: "extractImages", inputs: [samples.imagePDF],
                                             params: ["dpi": "72", "format": "png"])
            guard let first = outputs.first,
                  let image = try? ImageEngine.load(first) else {
                throw ZestError("no embedded image was extracted")
            }
            guard image.width == 640, image.height == 420 else {
                throw ZestError("extracted \(image.width)×\(image.height), expected 640×420")
            }
            return outputs
        }
        harness.check("PDF compress keeps mixed page sizes") {
            let outputs = try ToolRunner.run(tool: "compress", inputs: [samples.mixedPDF],
                                             params: ["percent": "10"])
            guard let first = outputs.first, let doc = PDFDocument(url: first),
                  doc.pageCount == 2,
                  let one = doc.page(at: 0)?.bounds(for: .mediaBox),
                  let two = doc.page(at: 1)?.bounds(for: .mediaBox) else {
                throw ZestError("compressed PDF lost pages")
            }
            guard abs(one.width - 612) < 2, abs(one.height - 792) < 2,
                  abs(two.width - 1000) < 2, abs(two.height - 500) < 2 else {
                throw ZestError("page boxes changed: \(one) \(two)")
            }
            return outputs
        }
        harness.check("PDF compression keeps text selectable") {
            // The vector path must survive compression: text stays real text,
            // not a picture of text.
            let textPDF = root.appendingPathComponent("text.pdf")
            try TextTools.pdf(from: "The quick brown fox jumps over the lazy dog",
                              to: textPDF)
            let compressed = try ToolRunner.run(tool: "compress", inputs: [textPDF],
                                                params: [:])
            guard let doc = PDFDocument(url: compressed[0]),
                  let text = doc.string else {
                throw ZestError("compressed PDF did not reopen")
            }
            guard text.contains("quick brown fox") else {
                throw ZestError("text was rasterized away by compression")
            }
            return compressed
        }

        harness.check("PDF compress") {
            try ToolRunner.run(tool: "compress", inputs: [pdf], params: [:])
        }
        harness.check("PDF strip metadata") {
            try ToolRunner.run(tool: "strip", inputs: [pdf], params: [:])
        }

        // Documents.
        harness.check("TXT → PDF") { try Convert.perform(samples.txt, to: format("pdf", for: .document)) }
        harness.check("TXT → DOCX") { try Convert.perform(samples.txt, to: format("docx", for: .document)) }
        harness.check("TXT → RTF") { try Convert.perform(samples.txt, to: format("rtf", for: .document)) }
        harness.check("TXT → HTML") { try Convert.perform(samples.txt, to: format("html", for: .document)) }
        harness.check("TXT → EPUB") { try Convert.perform(samples.txt, to: format("epub", for: .document)) }
        harness.check("DOCX → PDF") { try Convert.perform(samples.docx, to: format("pdf", for: .document)) }
        harness.check("DOCX → PDF (flowing layout)") {
            try Convert.perform(samples.docx, to: format("pdf", for: .document),
                                params: ["pdfLayout": "flowing"])
        }
        harness.check("DOCX → EPUB (fixed layout)") {
            let out = try Convert.perform(samples.docx, to: format("epub", for: .document),
                                          params: ["epubLayout": "fixed"])
            let listing = try Shell.run("/usr/bin/unzip", ["-l", out[0].path])
            guard listing.contains("images/page-1.jpg") else {
                throw ZestError("fixed layout has no page images")
            }
            return out
        }
        harness.check("DOCX → TXT") { try Convert.perform(samples.docx, to: format("txt", for: .document)) }
        harness.check("Markdown → HTML") { try Convert.perform(samples.md, to: format("html", for: .document)) }
        harness.check("Markdown → PDF") { try Convert.perform(samples.md, to: format("pdf", for: .document)) }
        harness.check("DOCX strip metadata") {
            try ToolRunner.run(tool: "strip", inputs: [samples.docx], params: [:])
        }

        // Spreadsheets.
        harness.check("CSV → XLSX") { try Convert.perform(samples.csv, to: format("xlsx", for: .sheet)) }
        harness.check("CSV → ODS") { try Convert.perform(samples.csv, to: format("ods", for: .sheet)) }
        harness.check("CSV → PDF") { try Convert.perform(samples.csv, to: format("pdf", for: .sheet)) }
        harness.check("XLSX → CSV") { try Convert.perform(samples.xlsx, to: format("csv", for: .sheet)) }
        harness.check("XLSX → ODS") { try Convert.perform(samples.xlsx, to: format("ods", for: .sheet)) }
        harness.check("XLSX → PDF") { try Convert.perform(samples.xlsx, to: format("pdf", for: .sheet)) }
        harness.check("ODS → CSV") {
            let ods = try Convert.perform(samples.csv, to: format("ods", for: .sheet))
            guard let first = ods.first else { throw ZestError("no ODS output") }
            return try Convert.perform(first, to: format("csv", for: .sheet))
        }

        // Subtitles.
        harness.check("SRT → VTT") { try Convert.perform(samples.srt, to: format("vtt", for: .subtitle)) }
        harness.check("SRT → TXT") { try Convert.perform(samples.srt, to: format("txt", for: .subtitle)) }
        harness.check("Subtitle shift") {
            try ToolRunner.run(tool: "shift", inputs: [samples.srt], params: ["seconds": "0.5"])
        }
        harness.check("Subtitle merge") {
            try ToolRunner.run(tool: "merge", inputs: [samples.srt, samples.srt2], params: [:])
        }

        // Archives.
        harness.check("Archive extract") {
            let dir = try ArchiveEngine.extract(samples.zip)
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            guard !contents.isEmpty else { throw ZestError("archive extracted empty") }
            return contents
        }
        harness.check("Archive extract tool") {
            let outputs = try ToolRunner.run(tool: "extract", inputs: [samples.zip], params: [:])
            guard let dir = outputs.first, dir.hasDirectoryPath else {
                throw ZestError("Extract tool did not return a folder")
            }
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            guard !contents.isEmpty else { throw ZestError("Extract tool produced an empty folder") }
            return outputs
        }
        harness.check("ZIP → TAR") {
            try Convert.perform(samples.zip, to: format("tar", for: .archive))
        }
        harness.check("Folder → ZIP") {
            [try ArchiveEngine.create(urls: [root], ext: "zip", baseName: "selftest-folder")]
        }
        harness.check("TXT → GZIP") {
            let out = try ArchiveEngine.create(urls: [samples.txt], ext: "gz",
                                               baseName: "selftest-gzip")
            let dir = try ArchiveEngine.extract(out)
            let text = try String(contentsOf: dir.appendingPathComponent("selftest-gzip"),
                                  encoding: .utf8)
            guard text.contains("Zest selftest") else {
                throw ZestError("gzip round trip lost the text")
            }
            return [out]
        }
        harness.check("Folder → GZIP → extracted folder") {
            let folder = root.appendingPathComponent("gzip-folder", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "inside".write(to: folder.appendingPathComponent("inside.txt"),
                               atomically: true, encoding: .utf8)
            let out = try ArchiveEngine.create(urls: [folder], ext: "gz",
                                               baseName: "selftest-archive")
            let dir = try ArchiveEngine.extract(out)
            guard FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("gzip-folder/inside.txt").path) else {
                throw ZestError("tar.gz contents were not extracted")
            }
            return [out]
        }

        // Media conversions and tools.
        if samples.ffmpeg {
            harness.check("MP4 → MOV") { try Convert.perform(samples.mp4, to: format("mov", for: .video)) }
            harness.check("MP4 → MP3") { try Convert.perform(samples.mp4, to: format("mp3", for: .video)) }
            harness.check("MP4 → GIF") { try Convert.perform(samples.mp4, to: format("gif", for: .video)) }
            if Capability.vorbisEncode {
            harness.check("WAV → OGG honours the bitrate default") {
                var params = Prefs.conversionParams(for: format("ogg", for: .audio))
                params["audioBitrate"] = "96k"
                return try Convert.perform(samples.wav, to: format("ogg", for: .audio), params: params)
            }
        } else {
            harness.skip += 1
            out("SKIP  WAV → OGG (ffmpeg has no libvorbis)")
        }
        harness.check("WAV → FLAC") { try Convert.perform(samples.wav, to: format("flac", for: .audio)) }
            harness.check("Media trim") {
                try ToolRunner.run(tool: "trim", inputs: [samples.mp4],
                                   params: ["start": "0", "end": "0.5"])
            }
            harness.check("Media split") {
                try ToolRunner.run(tool: "split", inputs: [samples.mp4], params: ["parts": "2"])
            }
            harness.check("Media join") {
                try ToolRunner.run(tool: "join", inputs: [samples.mp4, samples.mp42], params: [:])
            }
            harness.check("Media speed") {
                try ToolRunner.run(tool: "speed", inputs: [samples.mp4], params: ["factor": "1.5"])
            }
            harness.check("Media snapshot") {
                try ToolRunner.run(tool: "snapshot", inputs: [samples.mp4],
                                   params: ["time": "0.2", "format": "png"])
            }
            harness.check("Media snapshots") {
                let outputs = try ToolRunner.run(tool: "snapshots", inputs: [samples.mp4],
                                                 params: ["times": "0,0.2", "format": "png"])
                guard outputs.count == 2,
                      outputs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
                else { throw ZestError("Snapshots did not write both frames") }
                return outputs
            }
            harness.check("Media GIF tool") {
                try ToolRunner.run(tool: "gif", inputs: [samples.mp4],
                                   params: ["fps": "8", "width": "320"])
            }
            harness.check("Media mute") {
                try ToolRunner.run(tool: "mute", inputs: [samples.mp4], params: [:])
            }
            harness.check("Media extract audio") {
                try ToolRunner.run(tool: "extractAudio", inputs: [samples.mp4],
                                   params: ["format": "mp3"])
            }
            harness.check("Media normalize") {
                try ToolRunner.run(tool: "normalize", inputs: [samples.wav], params: ["lufs": "-16"])
            }
            harness.check("Media bleep") {
                try ToolRunner.run(tool: "bleep", inputs: [samples.wav],
                                   params: ["start": "0.1", "end": "0.3"])
            }
            harness.check("Media redact video") {
                guard let ffmpeg = ToolFinder.ffmpeg else { throw ZestError("ffmpeg required") }
                // A white clip makes the box assertion unambiguous.
                let solid = root.appendingPathComponent("solid.mp4")
                try Shell.run(ffmpeg, ["-y", "-f", "lavfi", "-i",
                                       "color=c=white:s=320x240:r=24:d=1",
                                       "-c:v", "libx264", "-pix_fmt", "yuv420p", solid.path])
                let outputs = try ToolRunner.run(
                    tool: "redactVideo", inputs: [solid],
                    params: ["x": "40", "y": "30", "w": "160", "h": "90",
                             "start": "0", "end": "0.6", "mode": "box"])
                let frames = root.appendingPathComponent("redact-frames", isDirectory: true)
                try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
                let inside = frames.appendingPathComponent("inside.png")
                let outside = frames.appendingPathComponent("outside.png")
                try MediaEngine.snapshot(outputs[0], at: 0.3, to: inside)
                try MediaEngine.snapshot(outputs[0], at: 0.85, to: outside)
                let masked = try pixel(in: inside, x: 120, y: 75)
                let clear = try pixel(in: outside, x: 120, y: 75)
                guard (masked.max() ?? 255) < 20 else {
                    throw ZestError("redacted pixel is not black (\(masked))")
                }
                guard (clear.min() ?? 0) > 200 else {
                    throw ZestError("pixel outside the range changed (\(clear))")
                }
                return outputs
            }
            harness.check("Media redact audio") {
                let outputs = try ToolRunner.run(tool: "redactAudio", inputs: [samples.wav],
                                                 params: ["start": "0.1", "end": "0.4",
                                                          "mode": "tone", "frequency": "880"])
                // The tone replaces the range; the rest of the track is untouched.
                let probe = ToolFinder.ffprobe
                if let probe {
                    let (status, _) = try Shell.runAllowFailure(probe, [
                        "-v", "error", "-show_entries", "format=duration",
                        "-of", "default=noprint_wrappers=1", outputs[0].path])
                    guard status == 0 else { throw ZestError("ffprobe can't read the redacted audio") }
                }
                return outputs
            }
            harness.check("Media audio to video") {
                let outputs = try ToolRunner.run(tool: "audioToVideo", inputs: [samples.wav],
                                                 params: ["width": "640", "height": "360",
                                                          "color": "#1C1C1E"])
                if let probe = ToolFinder.ffprobe {
                    let (status, text) = try Shell.runAllowFailure(probe, [
                        "-v", "error", "-show_entries", "stream=codec_type",
                        "-of", "csv=p=0", outputs[0].path])
                    guard status == 0, text.contains("video"), text.contains("audio") else {
                        throw ZestError("audio-to-video output is missing a stream: \(text)")
                    }
                }
                return outputs
            }
            harness.check("Media channels") {
                try ToolRunner.run(tool: "channels", inputs: [samples.wav], params: ["mode": "mono"])
            }
            harness.check("Media sample rate") {
                try ToolRunner.run(tool: "sampleRate", inputs: [samples.wav], params: ["rate": "22050"])
            }
            harness.check("Media compress") {
                try ToolRunner.run(tool: "compress", inputs: [samples.mp4], params: ["percent": "30"])
            }
            harness.check("Media strip metadata") {
                try ToolRunner.run(tool: "strip", inputs: [samples.mp4], params: [:])
            }
        } else {
            harness.skip += 23
            out("SKIP  23 media checks — ffmpeg is not installed")
        }
    }

    // MARK: Harness

    private struct Harness {
        var pass = 0
        var fail = 0
        var skip = 0

        mutating func check(_ label: String, _ body: () throws -> [URL]) {
            do {
                let outputs = try body()
                guard !outputs.isEmpty else { throw ZestError("no outputs") }
                for url in outputs { try verify(url) }
                pass += 1
                out("PASS  \(label)")
            } catch {
                fail += 1
                out("FAIL  \(label): \(error.localizedDescription)")
                Log.write("SELFTEST FAIL \(label): \(error.localizedDescription)")
            }
        }
    }

    /// Samples one pixel from an image file, top-left origin.
    private static func pixel(in url: URL, x: Int, y: Int) throws -> [UInt8] {
        let image = try ImageEngine.load(url)
        guard let slice = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            throw ZestError("can't crop \(url.lastPathComponent)")
        }
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ZestError("can't sample \(url.lastPathComponent)")
        }
        ctx.interpolationQuality = .none
        ctx.draw(slice, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(data.prefix(3))
    }

    private static func verify(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw ZestError("missing output \(url.lastPathComponent)")
        }
        guard url.fileSize > 0 else {
            throw ZestError("empty output \(url.lastPathComponent)")
        }
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
                throw ZestError("unreadable PDF \(url.lastPathComponent)")
            }
        case "docx", "xlsx", "pptx":
            let listing = try Shell.run("/usr/bin/unzip", ["-l", url.path])
            guard listing.contains("[Content_Types].xml") else {
                throw ZestError("OOXML parts not at archive root: \(url.lastPathComponent)")
            }
            guard !listing.contains("__MACOSX") else {
                throw ZestError("archive contains __MACOSX: \(url.lastPathComponent)")
            }
        case "epub", "ods":
            let listing = try Shell.run("/usr/bin/unzip", ["-l", url.path])
            guard listing.contains("mimetype") else {
                throw ZestError("mimetype not at archive root: \(url.lastPathComponent)")
            }
            guard !listing.contains("__MACOSX") else {
                throw ZestError("archive contains __MACOSX: \(url.lastPathComponent)")
            }
        case "png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif", "heic", "avif":
            guard (try? ImageEngine.load(url)) != nil else {
                throw ZestError("unreadable image \(url.lastPathComponent)")
            }
        case "mp4", "mov", "mkv", "webm", "avi", "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma":
            if let probe = ToolFinder.ffprobe {
                let (status, _) = try Shell.runAllowFailure(probe, [
                    "-v", "error", "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1", url.path
                ])
                guard status == 0 else {
                    throw ZestError("ffprobe can't read \(url.lastPathComponent)")
                }
            }
        default:
            break
        }
    }

    // MARK: Helpers

    private static func format(_ ext: String, for kind: Kind) -> Fmt {
        if let fmt = Catalog.formats(for: kind).first(where: { $0.ext == ext }) {
            return fmt
        }
        return Fmt(ext: ext, title: ext.uppercased(), outKind: kind, symbol: "doc")
    }

    private static func out(_ text: String) {
        print(text)
    }

    private static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static func usage() {
        out("""
        Zest — headless commands

          Zest formats <file>...
          Zest convert <file>... --to <ext>
          Zest tool <id> <file>... [--params key=value ...]
          Zest selftest
          Zest uitest
          Zest wheel <out.png> [--kind image] [--mode convert] [--hover N]

        Examples:
          Zest formats photo.heic
          Zest convert photo.png --to jpg
          Zest tool compress video.mp4 --params percent=40
          Zest tool metadata song.mp3 --params remove=1
          Zest wheel /tmp/wheel.png --kind pdf --mode tools
        """)
    }
}
