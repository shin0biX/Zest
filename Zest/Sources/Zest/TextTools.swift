import AppKit
import CoreText

// MARK: - Text tools

enum TextTools {
    static func plainFont(size: CGFloat = 11.5, bold: Bool = false) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    static func attributed(_ text: String, size: CGFloat = 11.5) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2.5
        para.paragraphSpacing = 5
        return NSAttributedString(string: text, attributes: [
            .font: plainFont(size: size),
            .foregroundColor: NSColor.black,
            .paragraphStyle: para
        ])
    }

    static func pdf(from text: String, to url: URL) throws {
        try pdf(from: attributed(text), to: url)
    }

    static func pdf(from attributed: NSAttributedString, to url: URL,
                    pageSize: CGSize = CGSize(width: 612, height: 792),
                    margin: CGFloat = 54) throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw ZestError("Couldn't create PDF")
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = box.insetBy(dx: margin, dy: margin)
        var location = 0
        var pages = 0

        while location < attributed.length {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: location, length: 0), path, nil)
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.textMatrix = .identity
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()
            ctx.endPDFPage()
            pages += 1
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            location += visible.length
        }

        if pages == 0 {
            ctx.beginPDFPage(nil)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    static func writeRTF(text: String, to url: URL) throws {
        var data: Data?
        onMainSync {
            let string = attributed(text)
            data = try? string.data(
                from: NSRange(location: 0, length: string.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        }
        guard let data else { throw ZestError("Couldn't build RTF") }
        try data.write(to: url)
    }

    static func writeRTF(attributed: NSAttributedString, to url: URL) throws {
        var data: Data?
        onMainSync {
            data = try? attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        }
        guard let data else { throw ZestError("Couldn't build RTF") }
        try data.write(to: url)
    }

    static func attributedFromRTF(_ data: Data) -> NSAttributedString? {
        var result: NSAttributedString?
        onMainSync {
            result = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
        }
        return result
    }

    static func textutilConvert(_ input: URL, to ext: String) throws -> URL {
        let out = Temp.dir().appendingPathComponent("converted.\(ext)")
        try Shell.run("/usr/bin/textutil", ["-convert", ext, "-output", out.path, input.path])
        return out
    }

    static func plainText(from input: URL) throws -> String {
        let kind = KindDetector.kind(of: input)
        if kind == .document, input.pathExtension.lowercased() == "docx" {
            return DocxReader.text(input)
        }
        if input.pathExtension.lowercased() == "txt" || input.pathExtension.lowercased() == "md"
            || input.pathExtension.lowercased() == "markdown" {
            return try String(contentsOf: input, encoding: .utf8)
        }
        if input.pathExtension.lowercased() == "html" || input.pathExtension.lowercased() == "htm" {
            let html = try String(contentsOf: input, encoding: .utf8)
            return stripHTML(html)
        }
        let converted = try textutilConvert(input, to: "txt")
        return (try? String(contentsOf: converted, encoding: .utf8)) ?? ""
    }

    static func attributedDocument(_ input: URL) throws -> NSAttributedString {
        let ext = input.pathExtension.lowercased()
        if ext == "docx" {
            return attributed(DocxReader.text(input))
        }
        if ext == "txt" || ext == "md" || ext == "markdown" {
            let text = try String(contentsOf: input, encoding: .utf8)
            return ext == "txt" ? attributed(text) : markdownToAttributed(text)
        }
        if ext == "rtf" {
            if let data = try? Data(contentsOf: input),
               let attr = attributedFromRTF(data) {
                return attr
            }
        }
        let rtf = try textutilConvert(input, to: "rtf")
        guard let data = try? Data(contentsOf: rtf),
              let attr = attributedFromRTF(data) else {
            let text = try plainText(from: input)
            return attributed(text)
        }
        return attr
    }

    // MARK: HTML

    static func html(text: String, title: String) -> String {
        let escaped = escapeXML(text)
            .components(separatedBy: "\n")
            .map { "<p>\($0)</p>" }
            .joined(separator: "\n")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escapeXML(title))</title>
        <style>body{font:15px -apple-system,Helvetica,sans-serif;line-height:1.5;max-width:720px;margin:48px auto;padding:0 20px;color:#111}p{margin:0 0 .8em}</style>
        </head><body>\(escaped)</body></html>
        """
    }

    static func markdownToHTML(_ md: String) -> String {
        var html: [String] = []
        var inList = false
        for raw in md.components(separatedBy: "\n") {
            var line = raw
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html.append("<ul>"); inList = true }
                line = String(line.dropFirst(2))
                html.append("<li>\(inlineHTML(line))</li>")
                continue
            }
            if inList { html.append("</ul>"); inList = false }
            if line.hasPrefix("### ") {
                html.append("<h3>\(inlineHTML(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                html.append("<h2>\(inlineHTML(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                html.append("<h1>\(inlineHTML(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("> ") {
                html.append("<blockquote>\(inlineHTML(String(line.dropFirst(2))))</blockquote>")
            } else if line.trimmed().isEmpty {
                html.append("")
            } else {
                html.append("<p>\(inlineHTML(line))</p>")
            }
        }
        if inList { html.append("</ul>") }
        return html.joined(separator: "\n")
    }

    private static func inlineHTML(_ text: String) -> String {
        var s = escapeXML(text)
        s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", with: "<em>$1</em>",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`",
                                   with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
                                   with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return s
    }

    static func markdownToAttributed(_ md: String, baseSize: CGFloat = 11.5) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 6

        func append(_ text: String, font: NSFont, spaceAfter: CGFloat = 6) {
            let p = para.mutableCopy() as! NSMutableParagraphStyle
            p.paragraphSpacing = spaceAfter
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: NSColor.black, .paragraphStyle: p
            ]))
        }

        for raw in md.components(separatedBy: "\n") {
            if raw.hasPrefix("# ") {
                append(String(raw.dropFirst(2)), font: .systemFont(ofSize: baseSize + 8, weight: .bold), spaceAfter: 10)
            } else if raw.hasPrefix("## ") {
                append(String(raw.dropFirst(3)), font: .systemFont(ofSize: baseSize + 4, weight: .bold), spaceAfter: 8)
            } else if raw.hasPrefix("### ") {
                append(String(raw.dropFirst(4)), font: .systemFont(ofSize: baseSize + 1.5, weight: .semibold), spaceAfter: 6)
            } else if raw.hasPrefix("- ") || raw.hasPrefix("* ") {
                append("• " + String(raw.dropFirst(2)), font: plainFont(size: baseSize), spaceAfter: 3)
            } else if raw.trimmed().isEmpty {
                append(" ", font: plainFont(size: baseSize), spaceAfter: 4)
            } else {
                let line = NSMutableAttributedString(string: raw, attributes: [
                    .font: plainFont(size: baseSize), .foregroundColor: NSColor.black
                ])
                applyInlineMarkdown(line, baseSize: baseSize)
                result.append(line)
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: plainFont(size: baseSize), .paragraphStyle: para
                ]))
            }
        }
        return result
    }

    private static func applyInlineMarkdown(_ string: NSMutableAttributedString, baseSize: CGFloat) {
        let text = string.string as NSString
        let patterns: [(String, [NSAttributedString.Key: Any])] = [
            ("\\*\\*(.+?)\\*\\*", [.font: NSFont.systemFont(ofSize: baseSize, weight: .bold)]),
            ("`([^`]+)`", [.font: NSFont.monospacedSystemFont(ofSize: baseSize - 0.5, weight: .regular)])
        ]
        for (pattern, attrs) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: string.string, range: NSRange(location: 0, length: text.length)) {
                string.addAttributes(attrs, range: match.range)
            }
        }
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?is)<(script|style).*?</\\1>",
                                         with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n\n",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(div|h[1-6]|li|tr)>", with: "\n",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "",
                                         options: .regularExpression)
        text = unescapeXML(text)
        return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmed()
    }

    // MARK: Entities

    static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func unescapeXML(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            let ns = out as NSString
            let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let hex = ns.substring(with: match.range(at: 1)) == "x"
                let digits = ns.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: hex ? 16 : 10),
                   let scalar = UnicodeScalar(value) {
                    out = (out as NSString).replacingCharacters(
                        in: match.range, with: String(Character(scalar)))
                }
            }
        }
        return out
    }
}

// MARK: - Zip

enum ZipUtil {
    static func zipDirectory(_ dir: URL, to out: URL, keepParent: Bool = false) throws {
        try? FileManager.default.removeItem(at: out)
        var args = ["-c", "-k", "--norsrc", "--noextattr"]
        if keepParent { args.append("--keepParent") }
        args += [dir.path, out.path]
        try Shell.run("/usr/bin/ditto", args)
    }

    static func unzip(_ archive: URL, to dir: URL) throws {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path])
    }

    static func zipEPUB(_ dir: URL, to out: URL) throws {
        try? FileManager.default.removeItem(at: out)
        try Shell.run("/usr/bin/zip", ["-X0", out.path, "mimetype"], cwd: dir)
        try Shell.run("/usr/bin/zip", ["-Xr9", out.path, "META-INF", "OEBPS"], cwd: dir)
    }
}

// MARK: - DOCX

struct DocBlock {
    var text: String
    var heading: Int? // 0 title, 1...6
    init(_ text: String, heading: Int? = nil) {
        self.text = text
        self.heading = heading
    }
}

enum DocxReader {
    static func text(_ url: URL) -> String {
        let dir = Temp.dir()
        guard (try? ZipUtil.unzip(url, to: dir)) != nil else { return "" }
        let doc = dir.appendingPathComponent("word/document.xml")
        guard let xml = try? String(contentsOf: doc, encoding: .utf8) else { return "" }
        var out = ""
        let paragraphs = matches("<w:p[ >].*?</w:p>", in: xml)
        for p in paragraphs {
            let texts = matches("<w:t[^>]*>(.*?)</w:t>", in: p)
            let line = texts.map { TextTools.unescapeXML($0) }.joined()
            out += line + "\n"
        }
        return out.trimmed()
    }

    static func blocks(_ url: URL) -> [DocBlock] {
        text(url).components(separatedBy: "\n").map { DocBlock($0) }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }
}

enum DocxWriter {
    static func write(paragraphs: [String], title: String? = nil, to out: URL) throws {
        var blocks: [DocBlock] = []
        if let title, !title.isEmpty { blocks.append(DocBlock(title, heading: 0)) }
        blocks += paragraphs.map { DocBlock($0) }
        try write(blocks: blocks, to: out)
    }

    static func write(blocks: [DocBlock], to out: URL) throws {
        let dir = Temp.dir()
        let word = dir.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)

        var body = ""
        for block in blocks {
            let style: String
            if let heading = block.heading {
                style = heading == 0 ? "Title" : "Heading\(min(6, max(1, heading)))"
            } else {
                style = "Normal"
            }
            let text = TextTools.escapeXML(block.text)
            body += """
            <w:p><w:pPr><w:pStyle w:val="\(style)"/></w:pPr><w:r><w:t xml:space="preserve">\(text)</w:t></w:r></w:p>

            """
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """
        try document.write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>
        </w:styles>
        """
        try styles.write(to: word.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        </Types>
        """
        try contentTypes.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        let relDir = dir.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: relDir, withIntermediateDirectories: true)
        try rels.write(to: relDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let docRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        let docRelDir = word.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: docRelDir, withIntermediateDirectories: true)
        try docRels.write(to: docRelDir.appendingPathComponent("document.xml.rels"),
                          atomically: true, encoding: .utf8)

        try ZipUtil.zipDirectory(dir, to: out)
    }
}

// MARK: - EPUB

enum EpubWriter {
    static func write(title: String, pages: [String], to out: URL) throws {
        let dir = Temp.dir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("META-INF"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("OEBPS"),
                                                withIntermediateDirectories: true)

        try "application/epub+zip".write(to: dir.appendingPathComponent("mimetype"),
                                         atomically: true, encoding: .utf8)

        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        try container.write(to: dir.appendingPathComponent("META-INF/container.xml"),
                            atomically: true, encoding: .utf8)

        var manifest = ""
        var spine = ""
        var navPoints = ""

        var chapters: [String] = []
        for (index, page) in pages.enumerated() {
            let body = page.components(separatedBy: "\n")
                .map { "<p>\(TextTools.escapeXML($0))</p>" }
                .joined(separator: "\n")
            let xhtml = """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page \(index + 1)</title>
            <link rel="stylesheet" type="text/css" href="style.css"/></head>
            <body><h1>Page \(index + 1)</h1>\(body.isEmpty ? "<p> </p>" : body)</body></html>
            """
            chapters.append(xhtml)
            manifest += "<item id=\"c\(index)\" href=\"chapter\(index).xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"c\(index)\"/>\n"
            navPoints += """
            <navPoint id="n\(index)" playOrder="\(index + 1)"><navLabel><text>Page \(index + 1)</text></navLabel><content src="chapter\(index).xhtml"/></navPoint>

            """
        }

        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>\(TextTools.escapeXML(title))</dc:title>
        <dc:language>en</dc:language>
        <dc:identifier id="bookid">urn:uuid:\(UUID().uuidString)</dc:identifier>
        </metadata>
        <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="css" href="style.css" media-type="text/css"/>
        \(manifest)</manifest>
        <spine toc="ncx">\(spine)</spine>
        </package>
        """
        try opf.write(to: dir.appendingPathComponent("OEBPS/content.opf"),
                      atomically: true, encoding: .utf8)

        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="urn:uuid:\(UUID().uuidString)"/><meta name="dtb:depth" content="1"/><meta name="dtb:totalPageCount" content="0"/><meta name="dtb:maxPageNumber" content="0"/></head>
        <docTitle><text>\(TextTools.escapeXML(title))</text></docTitle>
        <navMap>\(navPoints)</navMap>
        </ncx>
        """
        try ncx.write(to: dir.appendingPathComponent("OEBPS/toc.ncx"),
                      atomically: true, encoding: .utf8)

        let css = "body{font-family:-apple-system,Helvetica,sans-serif;line-height:1.55;margin:2em;}h1{font-size:1.4em;}p{margin:0 0 .8em;}"
        try css.write(to: dir.appendingPathComponent("OEBPS/style.css"),
                      atomically: true, encoding: .utf8)

        for (index, html) in chapters.enumerated() {
            try html.write(to: dir.appendingPathComponent("OEBPS/chapter\(index).xhtml"),
                           atomically: true, encoding: .utf8)
        }

        try ZipUtil.zipEPUB(dir, to: out)
    }
}
