import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreText

// MARK: - Image engine

enum ImageEngine {
    static func convert(_ input: URL, to fmt: Fmt, params: [String: String] = [:]) throws -> [URL] {
        if fmt.ext == "pdf" {
            return try PDFEngine.fromImages([input], params: params)
        }
        var image = try load(input)
        image = try ImageOps.apply(image, params: params)
        let out = Naming.output(for: input, ext: fmt.ext)
        var quality = Double(params["quality"] ?? "")
            ?? defaultQuality(for: fmt.ext)
        if params["imageCompression"] == "strong" {
            quality = max(0.05, quality * 0.75)
        }
        // Metadata travels natively through ImageIO — no external binary, so
        // preservation works on any Mac, not just hosts with exiftool.
        let properties = params["preserveMetadata"] != "0"
            ? metadataProperties(from: input)
            : nil
        try encode(image, to: out, ext: fmt.ext, quality: quality,
                   properties: properties)
        return [out]
    }

    /// The image dictionaries worth carrying across a conversion, with the
    /// per-pixel facts (dimensions, orientation) removed so a rotated or
    /// resized output is not mislabelled by stale tags.
    static func metadataProperties(from url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any] else { return nil }
        var carried: [CFString: Any] = [:]
        for key in [kCGImagePropertyTIFFDictionary, kCGImagePropertyExifDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary,
                    kCGImagePropertyPNGDictionary] {
            if let dict = props[key] { carried[key] = dict }
        }
        if let dpi = props[kCGImagePropertyDPIWidth] { carried[kCGImagePropertyDPIWidth] = dpi }
        if let dpi = props[kCGImagePropertyDPIHeight] { carried[kCGImagePropertyDPIHeight] = dpi }
        return carried.isEmpty ? nil : carried
    }

    static func defaultQuality(for ext: String) -> Double {
        switch Prefs.quality {
        case "light": return 0.88
        case "strong": return 0.55
        case "maximum": return 0.35
        default: return 0.75
        }
    }

    // MARK: Load

    static func load(_ url: URL) throws -> CGImage {
        if url.pathExtension.lowercased() == "svg" {
            return try renderSVG(url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ZestError("Can't read image \(url.lastPathComponent)")
        }
        guard var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ZestError("Can't decode image \(url.lastPathComponent)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation != 1 {
            let maxDim = max(image.width, image.height)
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDim
            ]
            if let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
                image = upright
            }
        }
        return image
    }

    private static func renderSVG(_ url: URL) throws -> CGImage {
        if let rsvg = ToolFinder.find("rsvg-convert") {
            let out = Temp.dir().appendingPathComponent("svg.png")
            try Shell.run(rsvg, ["-w", "2400", "-o", out.path, url.path])
            return try load(out)
        }
        if let magick = ToolFinder.find("magick") {
            let out = Temp.dir().appendingPathComponent("svg.png")
            try Shell.run(magick, ["-background", "none", "-density", "300", url.path, out.path])
            return try load(out)
        }
        let dir = Temp.dir()
        _ = try? Shell.runAllowFailure("/usr/bin/qlmanage",
                                       ["-t", "-s", "2400", "-o", dir.path, url.path])
        let candidates = (try? FileManager.default.contentsOfDirectory(at: dir,
                         includingPropertiesForKeys: nil)) ?? []
        guard let png = candidates.first(where: { $0.pathExtension.lowercased() == "png" })
                ?? candidates.first else {
            throw ZestError("Couldn't rasterize \(url.lastPathComponent). Install librsvg for better SVG output.")
        }
        return try load(png)
    }

    // MARK: Encode

    static func encode(_ image: CGImage, to url: URL, ext: String,
                       quality: Double, properties: [CFString: Any]? = nil) throws {
        let e = ext.lowercased()
        if e == "webp" { return try encodeWebP(image, to: url, quality: quality) }
        if e == "ico" { return try encodeWithFFmpeg(image, to: url, ext: e) }

        let prepared = (e == "jpg" || e == "jpeg" || e == "bmp")
            ? ImageOps.flatten(image, background: .white)
            : image

        guard let ut = UTType(filenameExtension: e),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, ut.identifier as CFString, 1, nil) else {
            return try encodeWithFFmpeg(image, to: url, ext: e)
        }

        var options: [CFString: Any] = properties ?? [:]
        options[kCGImagePropertyOrientation] = 1
        if e == "jpg" || e == "jpeg" || e == "heic" || e == "avif" {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        if e == "gif" {
            options[kCGImagePropertyGIFDictionary] = [
                kCGImagePropertyGIFLoopCount: 0
            ] as CFDictionary
        }
        CGImageDestinationAddImage(dest, prepared, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ZestError("Couldn't write \(url.lastPathComponent)")
        }
    }

    static func encodeData(_ image: CGImage, ext: String, quality: Double) -> Data? {
        let e = ext.lowercased()
        if e == "webp" {
            let tmp = Temp.dir()
            let url = tmp.appendingPathComponent("probe.webp")
            guard (try? encodeWebP(image, to: url, quality: quality)) != nil else { return nil }
            return try? Data(contentsOf: url)
        }
        guard let ut = UTType(filenameExtension: e),
              let data = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(
                data, ut.identifier as CFString, 1, nil) else { return nil }
        let prepared = (e == "jpg" || e == "jpeg") ? ImageOps.flatten(image, background: .white) : image
        var options: [CFString: Any] = [:]
        if e == "jpg" || e == "jpeg" || e == "heic" || e == "avif" {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, prepared, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func encodeWebP(_ image: CGImage, to url: URL, quality: Double) throws {
        let tmp = Temp.dir()
        let png = tmp.appendingPathComponent("source.png")
        try encode(image, to: png, ext: "png", quality: 1)

        if let cwebp = ToolFinder.cwebp {
            try Shell.run(cwebp, [
                "-quiet", "-q", "\(max(1, min(100, Int(quality * 100))))",
                "-mt", png.path, "-o", url.path
            ])
            return
        }
        if let ffmpeg = ToolFinder.ffmpeg {
            try Shell.run(ffmpeg, [
                "-y", "-i", png.path, "-c:v", "libwebp",
                "-quality", "\(max(1, min(100, Int(quality * 100))))",
                "-frames:v", "1", url.path
            ])
            return
        }
        throw ZestError("WebP output needs cwebp or ffmpeg.")
    }

    private static func encodeWithFFmpeg(_ image: CGImage, to url: URL, ext: String) throws {
        guard let ffmpeg = ToolFinder.ffmpeg else {
            throw ZestError("No encoder available for .\(ext)")
        }
        let tmp = Temp.dir()
        let png = tmp.appendingPathComponent("source.png")
        try encode(image, to: png, ext: "png", quality: 1)
        try Shell.run(ffmpeg, ["-y", "-i", png.path, "-frames:v", "1", url.path])
    }
}

// MARK: - Image operations

enum ImageOps {
    static func apply(_ image: CGImage, params: [String: String]) throws -> CGImage {
        var out = image

        if let crop = params["crop"], !crop.isEmpty,
           let rect = parseRect(crop) {
            out = cropImage(out, normalized: rect)
        }
        if let rotate = params["rotate"], let degrees = Double(rotate), degrees != 0 {
            out = rotateImage(out, degrees: degrees)
        }
        if let flip = params["flip"], !flip.isEmpty {
            out = flipImage(out, horizontal: flip == "horizontal")
        }
        if let w = Int(params["width"] ?? ""), w > 0 || Int(params["height"] ?? "") ?? 0 > 0 {
            let h = Int(params["height"] ?? "") ?? 0
            out = resize(out, width: w, height: h,
                         fit: params["fit"] ?? "fit")
        }
        if let maxDim = Int(params["maxDimension"] ?? ""), maxDim > 0 {
            let largest = max(out.width, out.height)
            if largest > maxDim {
                let scale = Double(maxDim) / Double(largest)
                out = resize(out, width: Int(Double(out.width) * scale),
                             height: Int(Double(out.height) * scale), fit: "stretch")
            }
        }
        if params["grayscale"] == "1" {
            out = grayscale(out)
        }
        let brightness = Double(params["brightness"] ?? "") ?? 0
        let contrast = Double(params["contrast"] ?? "") ?? 1
        let saturation = Double(params["saturation"] ?? "") ?? 1
        if brightness != 0 || contrast != 1 || saturation != 1 {
            out = adjust(out, brightness: brightness, contrast: contrast, saturation: saturation)
        }
        if let markdown = params["markup"], !markdown.isEmpty {
            out = markup(out, json: markdown)
        }
        return out
    }

    /// Add BG / frame: pad the photo on a coloured card, optionally with a
    /// fixed aspect, rounded corners, a border and a drop shadow.
    static func addBackground(_ image: CGImage, params: [String: String]) -> CGImage {
        let paddingPct = min(40, max(0, Double(params["padding"] ?? "10") ?? 10))
        let minSide = Double(min(image.width, image.height))
        let pad = max(0, Int((minSide * paddingPct / 100).rounded()))
        var contentW = image.width + pad * 2
        var contentH = image.height + pad * 2

        let ratioText = params["ratio"] ?? "original"
        let namedRatio: [String: Double] = [
            "square": 1, "4:3": 4.0 / 3.0, "16:9": 16.0 / 9.0,
            "9:16": 9.0 / 16.0, "3:2": 3.0 / 2.0
        ]
        if let ratio = namedRatio[ratioText] {
            let current = Double(contentW) / Double(contentH)
            if current > ratio {
                contentH = Int((Double(contentW) / ratio).rounded())
            } else {
                contentW = Int((Double(contentH) * ratio).rounded())
            }
        }

        let shadowStyle = params["shadow"] ?? "none"
        let margin = shadowStyle == "none" ? 0 : max(10, Int((minSide * 0.05).rounded()))
        let width = max(1, contentW + margin * 2)
        let height = max(1, contentH + margin * 2)
        let card = CGRect(x: CGFloat(margin), y: CGFloat(margin),
                          width: CGFloat(contentW), height: CGFloat(contentH))
        let border = max(0, Int(params["border"] ?? "0") ?? 0)
        let radiusPct = min(50, max(0, Double(params["radius"] ?? "4") ?? 4))
        let radius = Double(min(contentW, contentH)) * radiusPct / 100
        let pathRect = card.insetBy(dx: CGFloat(border) / 2, dy: CGFloat(border) / 2)
        let path = CGPath(roundedRect: pathRect,
                          cornerWidth: CGFloat(radius), cornerHeight: CGFloat(radius),
                          transform: nil)

        let background = NSColor(hex: params["background"] ?? "#FFFFFF") ?? .white
        let borderColor = NSColor(hex: params["borderColor"] ?? "#000000") ?? .black

        return canvas(width: width, height: height) { ctx in
            if shadowStyle != "none" {
                let strong = shadowStyle == "strong"
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: strong ? -10 : -5),
                              blur: CGFloat(strong ? 28 : 16),
                              color: NSColor.black.withAlphaComponent(strong ? 0.45 : 0.28).cgColor)
                ctx.setFillColor(background.cgColor)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.restoreGState()
            } else {
                ctx.setFillColor(background.cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }

            if border > 0 {
                ctx.addPath(path)
                ctx.setStrokeColor(borderColor.cgColor)
                ctx.setLineWidth(CGFloat(border))
                ctx.strokePath()
            }

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let imageRect = CGRect(x: card.midX - CGFloat(image.width) / 2,
                                   y: card.midY - CGFloat(image.height) / 2,
                                   width: CGFloat(image.width),
                                   height: CGFloat(image.height))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: imageRect)
            ctx.restoreGState()
        } ?? image
    }

    static func parseRect(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    static func canvas(width: Int, height: Int,
                       draw: (CGContext) -> Void) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    static func flatten(_ image: CGImage, background: NSColor) -> CGImage {
        canvas(width: image.width, height: image.height) { ctx in
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        } ?? image
    }

    static func resize(_ image: CGImage, width: Int, height: Int, fit: String) -> CGImage {
        var targetW = width
        var targetH = height
        let srcW = image.width, srcH = image.height

        if targetW <= 0 && targetH <= 0 { return image }
        if targetW <= 0 {
            targetW = max(1, Int(Double(srcW) * Double(targetH) / Double(srcH)))
        }
        if targetH <= 0 {
            targetH = max(1, Int(Double(srcH) * Double(targetW) / Double(srcW)))
        }

        switch fit {
        case "fill":
            let scale = max(Double(targetW) / Double(srcW), Double(targetH) / Double(srcH))
            let drawW = Int(Double(srcW) * scale)
            let drawH = Int(Double(srcH) * scale)
            return canvas(width: targetW, height: targetH) { ctx in
                ctx.draw(image, in: CGRect(x: (targetW - drawW) / 2,
                                           y: (targetH - drawH) / 2,
                                           width: drawW, height: drawH))
            } ?? image
        case "stretch":
            return canvas(width: targetW, height: targetH) { ctx in
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            } ?? image
        default: // fit
            let scale = min(Double(targetW) / Double(srcW), Double(targetH) / Double(srcH))
            let drawW = max(1, Int(Double(srcW) * scale))
            let drawH = max(1, Int(Double(srcH) * scale))
            return canvas(width: drawW, height: drawH) { ctx in
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: drawW, height: drawH))
            } ?? image
        }
    }

    static func cropImage(_ image: CGImage, normalized: CGRect) -> CGImage {
        let x = max(0, min(1, normalized.origin.x)) * CGFloat(image.width)
        let yNorm = max(0, min(1, normalized.origin.y))
        let w = max(0.01, min(1, normalized.width)) * CGFloat(image.width)
        let h = max(0.01, min(1, normalized.height)) * CGFloat(image.height)
        let y = (1 - yNorm - normalized.height) * CGFloat(image.height)
        let rect = CGRect(x: x, y: y, width: w, height: h).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 1, rect.height >= 1 else { return image }
        return image.cropping(to: rect) ?? image
    }

    static func rotateImage(_ image: CGImage, degrees: Double) -> CGImage {
        let radians = degrees * .pi / 180
        if degrees.truncatingRemainder(dividingBy: 90) == 0 {
            let normalized = ((degrees.truncatingRemainder(dividingBy: 360)) + 360)
                .truncatingRemainder(dividingBy: 360)
            let w = image.width, h = image.height
            let swap = normalized == 90 || normalized == 270
            let outW = swap ? h : w
            let outH = swap ? w : h
            return canvas(width: outW, height: outH) { ctx in
                ctx.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
                ctx.rotate(by: radians)
                ctx.draw(image, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2,
                                           width: CGFloat(w), height: CGFloat(h)))
            } ?? image
        }
        let w = Double(image.width), h = Double(image.height)
        let outW = Int(abs(cos(radians)) * w + abs(sin(radians)) * h)
        let outH = Int(abs(sin(radians)) * w + abs(cos(radians)) * h)
        return canvas(width: outW, height: outH) { ctx in
            ctx.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
            ctx.rotate(by: radians)
            ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        } ?? image
    }

    static func flipImage(_ image: CGImage, horizontal: Bool) -> CGImage {
        canvas(width: image.width, height: image.height) { ctx in
            ctx.translateBy(x: horizontal ? CGFloat(image.width) : 0,
                            y: horizontal ? 0 : CGFloat(image.height))
            ctx.scaleBy(x: horizontal ? -1 : 1, y: horizontal ? 1 : -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0,
                                       width: image.width, height: image.height))
        } ?? image
    }

    static func adjust(_ image: CGImage, brightness: Double,
                       contrast: Double, saturation: Double) -> CGImage {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(output, from: output.extent) else { return image }
        return cg
    }

    static func grayscale(_ image: CGImage) -> CGImage {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(output, from: output.extent) else { return image }
        return cg
    }

    // MARK: Markup

    static func markup(_ image: CGImage, json: String) -> CGImage {
        guard let data = json.data(using: .utf8),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = doc["ops"] as? [[String: Any]] else { return image }

        let W = CGFloat(image.width), H = CGFloat(image.height)
        return canvas(width: image.width, height: image.height) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            func point(_ value: [Double]) -> CGPoint {
                CGPoint(x: value[0] * W, y: (1 - value[1]) * H)
            }
            func color(_ value: [Double]?) -> CGColor {
                guard let value, value.count >= 3 else { return NSColor.systemRed.cgColor }
                let a = value.count > 3 ? value[3] : 1
                return NSColor(srgbRed: value[0], green: value[1],
                               blue: value[2], alpha: a).cgColor
            }

            for op in ops {
                let kind = op["t"] as? String ?? ""
                switch kind {
                case "rect":
                    guard let rect = op["rect"] as? [Double], rect.count == 4 else { continue }
                    let r = CGRect(x: rect[0] * W, y: (1 - rect[1] - rect[3]) * H,
                                   width: rect[2] * W, height: rect[3] * H)
                    if op["fill"] as? Bool == true {
                        ctx.setFillColor(color(op["color"] as? [Double]))
                        ctx.fill(r)
                    }
                    if let width = op["width"] as? Double, width > 0 {
                        ctx.setStrokeColor(color(op["color"] as? [Double]))
                        ctx.setLineWidth(max(1, CGFloat(width) * W))
                        ctx.stroke(r)
                    }
                case "pen":
                    guard let pts = op["points"] as? [[Double]], pts.count > 1 else { continue }
                    ctx.setStrokeColor(color(op["color"] as? [Double]))
                    ctx.setLineWidth(max(1, CGFloat(op["width"] as? Double ?? 0.004) * W))
                    ctx.beginPath()
                    ctx.move(to: point(pts[0]))
                    for p in pts.dropFirst() { ctx.addLine(to: point(p)) }
                    ctx.strokePath()
                case "arrow":
                    guard let a = op["from"] as? [Double], let b = op["to"] as? [Double] else { continue }
                    let p0 = point(a), p1 = point(b)
                    ctx.setStrokeColor(color(op["color"] as? [Double]))
                    let width = max(1, CGFloat(op["width"] as? Double ?? 0.005) * W)
                    ctx.setLineWidth(width)
                    ctx.beginPath()
                    ctx.move(to: p0)
                    ctx.addLine(to: p1)
                    ctx.strokePath()
                    let angle = atan2(p1.y - p0.y, p1.x - p0.x)
                    let head = max(10, width * 4)
                    let left = CGPoint(x: p1.x - cos(angle - .pi / 7) * head,
                                       y: p1.y - sin(angle - .pi / 7) * head)
                    let right = CGPoint(x: p1.x - cos(angle + .pi / 7) * head,
                                        y: p1.y - sin(angle + .pi / 7) * head)
                    ctx.beginPath()
                    ctx.move(to: p1)
                    ctx.addLine(to: left)
                    ctx.addLine(to: right)
                    ctx.closePath()
                    ctx.fillPath()
                case "text":
                    guard let text = op["text"] as? String,
                          let p = op["at"] as? [Double] else { continue }
                    let frac = op["size"] as? Double ?? 0.03
                    let size = max(8, frac * W)
                    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor(cgColor: color(op["color"] as? [Double]))
                            ?? NSColor.systemRed
                    ]
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(string: text, attributes: attrs))
                    ctx.textMatrix = .identity
                    let anchor = point(p)
                    ctx.textPosition = CGPoint(x: anchor.x, y: anchor.y - size * 0.9)
                    CTLineDraw(line, ctx)
                default:
                    break
                }
            }
        } ?? image
    }
}
