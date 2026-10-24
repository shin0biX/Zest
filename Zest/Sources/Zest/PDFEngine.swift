import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import Vision

enum PDFEngine {
    // MARK: Conversion

    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else {
            throw ZestError("Can't open \(input.lastPathComponent)")
        }
        switch fmt.ext.lowercased() {
        case "jpg", "jpeg", "png", "tiff":
            return try renderPages(doc, input: input, ext: fmt.ext,
                                   dpi: Double(params["dpi"] ?? "") ?? 300)
        case "txt":
            let out = Naming.output(for: input, ext: "txt")
            try textPages(doc).joined(separator: "\n\n").write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "md":
            let out = Naming.output(for: input, ext: "md")
            let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                ?? input.deletingPathExtension().lastPathComponent
            var md = "# \(title)\n\n"
            for (i, page) in textPages(doc).enumerated() {
                md += "## Page \(i + 1)\n\n\(page)\n\n"
            }
            try md.write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case "docx":
            let out = Naming.output(for: input, ext: "docx")
            try DocxWriter.write(paragraphs: textPages(doc).flatMap { $0.components(separatedBy: "\n") },
                                 title: input.deletingPathExtension().lastPathComponent,
                                 to: out)
            return [out]
        case "pptx":
            let out = Naming.output(for: input, ext: "pptx")
            let images = try renderPageImages(doc, dpi: 150)
            try PptxWriter.write(images: images, to: out)
            return [out]
        case "xlsx":
            let out = Naming.output(for: input, ext: "xlsx")
            var rows: [[String]] = []
            for (i, page) in textPages(doc).enumerated() {
                rows.append(["Page \(i + 1)"])
                rows.append(contentsOf: page.components(separatedBy: "\n").map { line in
                    line.components(separatedBy: "  ").filter { !$0.isEmpty }
                })
                rows.append([])
            }
            try XlsxWriter.write(rows: rows, sheetName: "PDF", to: out)
            return [out]
        case "epub":
            let out = Naming.output(for: input, ext: "epub")
            if params["epubLayout"] == "fixed" {
                try writeFixedEPUB(doc, input: input, to: out)
            } else {
                try EpubWriter.write(title: input.deletingPathExtension().lastPathComponent,
                                     pages: textPages(doc), to: out)
            }
            return [out]
        case "rtf":
            let out = Naming.output(for: input, ext: "rtf")
            let text = textPages(doc).joined(separator: "\n\n")
            try TextTools.writeRTF(text: text, to: out)
            return [out]
        default:
            throw ZestError("No PDF converter for .\(fmt.ext)")
        }
    }

    // MARK: Build

    static func fromImages(_ inputs: [URL], params: [String: String] = [:]) throws -> [URL] {
        guard !inputs.isEmpty else { return [] }
        let out = inputs.count == 1
            ? Naming.output(for: inputs[0], ext: "pdf")
            : Naming.batchOutput(for: inputs, ext: "pdf")
        let images = try inputs.map { try ImageEngine.load($0) }

        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else {
            throw ZestError("Couldn't create PDF")
        }
        for image in images {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(box)
            let inset: CGFloat = 18
            let available = box.insetBy(dx: inset, dy: inset)
            let scale = min(available.width / CGFloat(image.width),
                            available.height / CGFloat(image.height))
            let w = CGFloat(image.width) * scale
            let h = CGFloat(image.height) * scale
            ctx.draw(image, in: CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2,
                                       width: w, height: h))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return [out]
    }

    static func buildPDF(images: [CGImage], to out: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else {
            throw ZestError("Couldn't create PDF")
        }
        for image in images {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(box)
            let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
            let w = CGFloat(image.width) * scale
            let h = CGFloat(image.height) * scale
            ctx.draw(image, in: CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2,
                                       width: w, height: h))
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// Fixed-layout EPUB: each page becomes an image with its own viewport.
    static func writeFixedEPUB(_ doc: PDFDocument, input: URL, to out: URL) throws {
        let images = try renderPageImages(doc, dpi: 144)
        guard !images.isEmpty else { throw ZestError("No pages rendered") }
        try EpubWriter.writeFixed(
            title: input.deletingPathExtension().lastPathComponent,
            images: images, to: out)
    }

    // MARK: Render

    static func renderPages(_ doc: PDFDocument, input: URL, ext: String, dpi: Double) throws -> [URL] {
        let base = Naming.output(for: input, ext: ext)
        var outputs: [URL] = []
        let stem = base.deletingPathExtension().path
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index),
                  let image = render(page: page, dpi: dpi) else { continue }
            let url = URL(fileURLWithPath: "\(stem)-\(index + 1).\(ext)")
            try ImageEngine.encode(image, to: url, ext: ext, quality: 0.9)
            outputs.append(url)
        }
        guard !outputs.isEmpty else { throw ZestError("No pages rendered") }
        return outputs
    }

    static func renderPageImages(_ doc: PDFDocument, dpi: Double) throws -> [CGImage] {
        (0..<doc.pageCount).compactMap { index in
            doc.page(at: index).flatMap { render(page: $0, dpi: dpi) }
        }
    }

    static func render(page: PDFPage, dpi: Double) -> CGImage? {
        guard let cgPage = page.pageRef else { return nil }
        let box = cgPage.getBoxRect(.mediaBox)
        let scale = dpi / 72.0
        let width = max(1, Int(box.width * scale))
        let height = max(1, Int(box.height * scale))
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: target,
                                                  rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(cgPage)
        return ctx.makeImage()
    }

    static func textPages(_ doc: PDFDocument) -> [String] {
        (0..<doc.pageCount).map { index in
            let text = doc.page(at: index)?.string ?? ""
            guard text.trimmed().isEmpty else { return text }
            // Scanned pages have no text layer: read the rasterized page instead.
            guard let page = doc.page(at: index),
                  let image = render(page: page, dpi: 220) else { return text }
            let recognized = VisionOCR.text(from: image)
            return recognized.isEmpty ? text : recognized
        }
    }

    // MARK: Compression

    static func compress(_ input: URL, targetBytes: Int64?, to out: URL) throws {
        guard let doc = PDFDocument(url: input) else {
            throw ZestError("Can't open PDF")
        }
        let presets: [(Double, Double)] = {
            switch Prefs.quality {
            case "light": return [(200, 0.82), (160, 0.7), (130, 0.58)]
            case "strong": return [(120, 0.55), (96, 0.45), (72, 0.35)]
            case "maximum": return [(96, 0.45), (72, 0.35), (60, 0.28)]
            default: return [(150, 0.7), (120, 0.55), (96, 0.45), (72, 0.35)]
            }
        }()

        let best = out
        var bestSize = Int64.max
        for (dpi, quality) in presets {
            let candidate = Temp.dir().appendingPathComponent("compressed.pdf")
            try buildCompressed(doc: doc, dpi: dpi, quality: quality, to: candidate)
            let size = candidate.fileSize
            if size < bestSize {
                bestSize = size
                try? FileManager.default.removeItem(at: best)
                try FileManager.default.copyItem(at: candidate, to: best)
            }
            if let targetBytes, size <= targetBytes { break }
        }
        guard bestSize != Int64.max else { throw ZestError("PDF compression failed") }
    }

    private static func buildCompressed(doc: PDFDocument, dpi: Double,
                                        quality: Double, to out: URL) throws {
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(out as CFURL, mediaBox: &defaultBox, nil) else {
            throw ZestError("Couldn't write PDF")
        }
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let media = page.pageRef?.getBoxRect(.mediaBox) ?? defaultBox
            var pageBox = media
            let info: [CFString: Any] = [
                kCGPDFContextMediaBox: Data(bytes: &pageBox,
                                            count: MemoryLayout<CGRect>.size)
            ]
            ctx.beginPDFPage(info as CFDictionary)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(media)
            if let image = render(page: page, dpi: dpi),
               let data = ImageEngine.encodeData(image, ext: "jpg", quality: quality),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let jpeg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                ctx.draw(jpeg, in: media)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    // MARK: Page operations

    static func merge(_ inputs: [URL], to out: URL) throws {
        let doc = PDFDocument()
        for url in inputs {
            guard let source = PDFDocument(url: url) else { continue }
            for index in 0..<source.pageCount {
                if let page = source.page(at: index)?.copy() as? PDFPage {
                    doc.insert(page, at: doc.pageCount)
                }
            }
        }
        guard doc.pageCount > 0 else { throw ZestError("No pages to merge") }
        guard doc.write(to: out) else { throw ZestError("Couldn't write merged PDF") }
    }

    static func split(_ input: URL, ranges: String) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else { throw ZestError("Can't open PDF") }
        let eachPage = ranges.trimmed().isEmpty || ranges.lowercased() == "each"
        let rangesList = eachPage ? [] : parseRanges(ranges, pageCount: doc.pageCount)
        let labels: [String] = eachPage
            ? (0..<doc.pageCount).map { "page-\($0 + 1)" }
            : rangesList.map { range in
                range.count == 1
                    ? "p\(range[0] + 1)"
                    : "p\(range[0] + 1)-\(range[range.count - 1] + 1)"
            }

        // The source itself occupies "<stem>.pdf", so the old Naming.output base
        // always collided and page files inherited a spurious " 2". Pick a stem
        // whose page outputs do not exist; under replace, reuse the plain stem.
        let directory = input.deletingLastPathComponent()
        let name = input.deletingPathExtension().lastPathComponent
        var stem = directory.appendingPathComponent(name).path
        if Prefs.collisionPolicy != "replace" {
            var run = 2
            while labels.contains(where: {
                FileManager.default.fileExists(atPath: "\(stem)-\($0).pdf")
            }) {
                stem = directory.appendingPathComponent("\(name) \(run)").path
                run += 1
            }
        }

        var outputs: [URL] = []

        if eachPage {
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index)?.copy() as? PDFPage else { continue }
                let outDoc = PDFDocument()
                outDoc.insert(page, at: 0)
                let url = URL(fileURLWithPath: "\(stem)-page-\(index + 1).pdf")
                guard outDoc.write(to: url) else { continue }
                outputs.append(url)
            }
            return outputs
        }

        for (range, label) in zip(rangesList, labels) {
            let outDoc = PDFDocument()
            for index in range {
                if let page = doc.page(at: index)?.copy() as? PDFPage {
                    outDoc.insert(page, at: outDoc.pageCount)
                }
            }
            guard outDoc.pageCount > 0 else { continue }
            let url = URL(fileURLWithPath: "\(stem)-\(label).pdf")
            guard outDoc.write(to: url) else { continue }
            outputs.append(url)
        }
        return outputs
    }

    static func reorder(_ input: URL, spec: String) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else { throw ZestError("Can't open PDF") }
        let out = Naming.output(for: input, ext: "pdf", suffix: "reordered")
        let result = PDFDocument()
        for index in parseOrder(spec, pageCount: doc.pageCount) {
            if let page = doc.page(at: index)?.copy() as? PDFPage {
                result.insert(page, at: result.pageCount)
            }
        }
        guard result.pageCount > 0 else { throw ZestError("The page order was empty") }
        guard result.write(to: out) else { throw ZestError("Couldn't write PDF") }
        return [out]
    }

    static func rotate(_ input: URL, degrees: Int, pages: String) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else { throw ZestError("Can't open PDF") }
        let indices = pages.trimmed().isEmpty
            ? Array(0..<doc.pageCount)
            : parseOrder(pages, pageCount: doc.pageCount)
        for index in indices {
            guard let page = doc.page(at: index) else { continue }
            page.rotation = (page.rotation + degrees) % 360
        }
        let out = Naming.output(for: input, ext: "pdf", suffix: "rotated")
        guard doc.write(to: out) else { throw ZestError("Couldn't write PDF") }
        return [out]
    }

    static func extractImages(_ input: URL, dpi: Double, ext: String) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else { throw ZestError("Can't open PDF") }

        let embedded = embeddedImages(doc)
        if !embedded.isEmpty {
            let base = Naming.output(for: input, ext: ext, suffix: "img")
            let stem = base.deletingPathExtension().path
            var outputs: [URL] = []
            for item in embedded {
                let url = URL(fileURLWithPath:
                    "\(stem)-p\(item.page + 1)-\(item.index + 1).\(ext)")
                try ImageEngine.encode(item.image, to: url, ext: ext, quality: 0.92)
                outputs.append(url)
            }
            return outputs
        }

        // No image objects (or none we can decode): rasterize the pages.
        let base = Naming.output(for: input, ext: ext, suffix: "page")
        let stem = base.deletingPathExtension().path
        var outputs: [URL] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index), let image = render(page: page, dpi: dpi) else { continue }
            let url = URL(fileURLWithPath: "\(stem)-\(index + 1).\(ext)")
            try ImageEngine.encode(image, to: url, ext: ext, quality: 0.92)
            outputs.append(url)
        }
        return outputs
    }

    // MARK: Embedded images

    private static func embeddedImages(_ doc: PDFDocument) -> [(page: Int, index: Int, image: CGImage)] {
        var out: [(Int, Int, CGImage)] = []
        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex)?.pageRef else { continue }
            let streams = imageStreams(in: page)
            for (index, stream) in streams.enumerated() {
                if let image = decode(stream: stream) {
                    out.append((pageIndex, index, image))
                }
            }
        }
        return out
    }

    private static func imageStreams(in page: CGPDFPage) -> [CGPDFStreamRef] {
        guard let pageDict = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources else { return [] }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects),
              let xobjects else { return [] }

        final class Box { var streams: [CGPDFStreamRef] = [] }
        let box = Box()
        let info = Unmanaged.passUnretained(box).toOpaque()
        CGPDFDictionaryApplyFunction(xobjects, { _, object, info in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dict = CGPDFStreamGetDictionary(stream) else { return }
            var subtype: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtype),
                  let subtype, String(cString: subtype) == "Image" else { return }
            box.streams.append(stream)
        }, info)
        return box.streams
    }

    private static func decode(stream: CGPDFStreamRef) -> CGImage? {
        guard let dict = CGPDFStreamGetDictionary(stream) else { return nil }
        var width = 0
        var height = 0
        guard CGPDFDictionaryGetInteger(dict, "Width", &width),
              CGPDFDictionaryGetInteger(dict, "Height", &height),
              width > 0, height > 0 else { return nil }

        var isMask = false
        CGPDFDictionaryGetBoolean(dict, "ImageMask", &isMask)
        guard !isMask else { return nil }

        var bits = 8
        if !CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bits) { bits = 8 }
        guard [1, 2, 4, 8, 16].contains(bits) else { return nil }

        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return nil }

        if format == .jpegEncoded || format == .JPEG2000 {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return masked(image, dict: dict)
            }
        }

        guard let space = colorSpace(from: dict) else { return nil }
        let components = space.numberOfComponents
        let bitsPerPixel = space.model == .indexed ? bits : components * bits
        let bytesPerRow = (width * bitsPerPixel + 7) / 8
        guard data.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: data as CFData) else { return nil }

        var bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        if bits == 16 { bitmapInfo.insert(.byteOrder16Big) }

        guard let image = CGImage(
            width: width, height: height,
            bitsPerComponent: bits, bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: bitmapInfo, provider: provider,
            decode: decodeArray(from: dict),
            shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return masked(image, dict: dict)
    }

    private static func masked(_ image: CGImage, dict: CGPDFDictionaryRef) -> CGImage {
        var maskStream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dict, "SMask", &maskStream),
              let maskStream,
              let mask = decode(stream: maskStream),
              mask.width == image.width, mask.height == image.height else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.clip(to: rect, mask: mask)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    private static func decodeArray(from dict: CGPDFDictionaryRef) -> [CGFloat]? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "Decode", &array), let array else { return nil }
        let count = CGPDFArrayGetCount(array)
        guard count > 0 else { return nil }
        var out: [CGFloat] = []
        for index in 0..<count {
            var value: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
            out.append(CGFloat(value))
        }
        return out
    }

    private static func colorSpace(from dict: CGPDFDictionaryRef) -> CGColorSpace? {
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dict, "ColorSpace", &object),
              let object else { return nil }
        return colorSpace(from: object)
    }

    private static func colorSpace(from object: CGPDFObjectRef) -> CGColorSpace? {
        switch CGPDFObjectGetType(object) {
        case .name:
            var name: UnsafePointer<Int8>?
            guard CGPDFObjectGetValue(object, .name, &name), let name else { return nil }
            return colorSpace(named: String(cString: name))
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array,
                  CGPDFArrayGetCount(array) > 0 else { return nil }
            var name: UnsafePointer<Int8>?
            guard CGPDFArrayGetName(array, 0, &name), let name else { return nil }
            let kind = String(cString: name)
            if kind == "ICCBased" {
                var stream: CGPDFStreamRef?
                guard CGPDFArrayGetStream(array, 1, &stream), let stream,
                      var format = Optional(CGPDFDataFormat.raw),
                      let data = CGPDFStreamCopyData(stream, &format) as Data?,
                      let space = CGColorSpace(iccData: data as CFData) else { return nil }
                return space
            }
            if kind == "Indexed" {
                var baseObject: CGPDFObjectRef?
                var last = 0
                var lookup: CGPDFStringRef?
                guard CGPDFArrayGetObject(array, 1, &baseObject), let baseObject,
                      CGPDFArrayGetInteger(array, 2, &last),
                      CGPDFArrayGetString(array, 3, &lookup), let lookup,
                      let base = colorSpace(from: baseObject),
                      let bytes = CGPDFStringGetBytePtr(lookup) else { return nil }
                let count = CGPDFStringGetLength(lookup)
                let table = Data(bytes: bytes, count: count)
                return table.withUnsafeBytes { raw in
                    guard let pointer = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                    return CGColorSpace(indexedBaseSpace: base, last: last,
                                        colorTable: pointer)
                }
            }
            if kind == "CalRGB" { return CGColorSpaceCreateDeviceRGB() }
            if kind == "CalGray" { return CGColorSpaceCreateDeviceGray() }
            return nil
        default:
            return nil
        }
    }

    private static func colorSpace(named name: String) -> CGColorSpace? {
        switch name {
        case "DeviceRGB", "RGB": return CGColorSpaceCreateDeviceRGB()
        case "DeviceGray", "G": return CGColorSpaceCreateDeviceGray()
        case "DeviceCMYK", "CMYK": return CGColorSpaceCreateDeviceCMYK()
        case "CalRGB": return CGColorSpaceCreateDeviceRGB()
        case "CalGray": return CGColorSpaceCreateDeviceGray()
        default: return nil
        }
    }

    // MARK: Metadata / QR

    static func metadata(_ input: URL) -> [(String, String)] {
        guard let doc = PDFDocument(url: input) else { return [] }
        var out: [(String, String)] = [("Pages", "\(doc.pageCount)")]
        let attrs = doc.documentAttributes ?? [:]
        let mapping: [(PDFDocumentAttribute, String)] = [
            (.titleAttribute, "Title"),
            (.authorAttribute, "Author"),
            (.subjectAttribute, "Subject"),
            (.keywordsAttribute, "Keywords"),
            (.creatorAttribute, "Creator"),
            (.producerAttribute, "Producer"),
            (.creationDateAttribute, "Created"),
            (.modificationDateAttribute, "Modified")
        ]
        for (key, label) in mapping {
            if let value = attrs[key] {
                out.append((label, "\(value)"))
            }
        }
        return out
    }

    static func applyMetadata(_ input: URL, values: [String: String], remove: Bool) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else { throw ZestError("Can't open PDF") }
        let out = Naming.output(for: input, ext: "pdf", suffix: "metadata")
        if remove {
            let clean = PDFDocument()
            for index in 0..<doc.pageCount {
                if let page = doc.page(at: index)?.copy() as? PDFPage {
                    clean.insert(page, at: clean.pageCount)
                }
            }
            guard clean.write(to: out) else { throw ZestError("Couldn't write PDF") }
            return [out]
        }
        var attrs = doc.documentAttributes ?? [:]
        func set(_ key: PDFDocumentAttribute, _ name: String) {
            if let v = values[name], !v.isEmpty { attrs[key] = v }
        }
        set(.titleAttribute, "Title")
        set(.authorAttribute, "Author")
        set(.subjectAttribute, "Subject")
        set(.keywordsAttribute, "Keywords")
        doc.documentAttributes = attrs
        guard doc.write(to: out) else { throw ZestError("Couldn't write PDF") }
        return [out]
    }

    static func qrCodes(_ input: URL) -> [String] {
        guard let doc = PDFDocument(url: input),
              let page = doc.page(at: 0),
              let image = render(page: page, dpi: 220) else { return [] }
        return VisionQR.detect(image)
    }

    // MARK: Ranges

    static func parseRanges(_ spec: String, pageCount: Int) -> [[Int]] {
        var ranges: [[Int]] = []
        for token in spec.split(separator: ",") {
            let text = String(token).trimmed()
            if text.contains("-") {
                let bits = text.split(separator: "-").compactMap { Int(String($0).trimmed()) }
                guard bits.count == 2 else { continue }
                let start = max(1, min(bits[0], bits[1])) - 1
                let end = min(pageCount - 1, max(bits[0], bits[1]) - 1)
                if start <= end { ranges.append(Array(start...end)) }
            } else if let n = Int(text), n >= 1, n <= pageCount {
                ranges.append([n - 1])
            }
        }
        if ranges.isEmpty { ranges = (0..<pageCount).map { [$0] } }
        return ranges
    }

    static func parseOrder(_ spec: String, pageCount: Int) -> [Int] {
        var order: [Int] = []
        for token in spec.split(separator: ",") {
            let text = String(token).trimmed()
            if text.contains("-") {
                let bits = text.split(separator: "-").compactMap { Int(String($0).trimmed()) }
                guard bits.count == 2 else { continue }
                let step = bits[0] <= bits[1] ? 1 : -1
                var n = bits[0]
                while step > 0 ? n <= bits[1] : n >= bits[1] {
                    if n >= 1, n <= pageCount { order.append(n - 1) }
                    n += step
                }
            } else if let n = Int(text), n >= 1, n <= pageCount {
                order.append(n - 1)
            }
        }
        return order.isEmpty ? Array(0..<pageCount) : order
    }
}

// MARK: - Vision OCR

enum VisionOCR {
    static func text(from image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return "" }

        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

// MARK: - Vision QR

enum VisionQR {
    static func detect(_ image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let results = request.results ?? []
        var seen = Set<String>()
        var out: [String] = []
        for result in results {
            guard let value = result.payloadStringValue, !value.isEmpty else { continue }
            if seen.insert(value).inserted { out.append(value) }
        }
        return out
    }
}
