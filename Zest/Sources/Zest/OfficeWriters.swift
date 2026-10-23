import AppKit

// MARK: - PPTX

enum PptxWriter {
    private static let slideW = 12192000
    private static let slideH = 6858000

    static func write(images: [CGImage], to out: URL) throws {
        guard !images.isEmpty else { throw ZestError("No pages for PPTX") }
        let dir = Temp.dir()
        let ppt = dir.appendingPathComponent("ppt", isDirectory: true)
        try FileManager.default.createDirectory(at: ppt.appendingPathComponent("slides"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ppt.appendingPathComponent("media"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ppt.appendingPathComponent("slideLayouts"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ppt.appendingPathComponent("slideMasters"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ppt.appendingPathComponent("theme"),
                                                withIntermediateDirectories: true)

        var slideIds = ""
        var slideRels = ""
        var contentOverrides = ""

        for (index, image) in images.enumerated() {
            let number = index + 1
            let media = ppt.appendingPathComponent("media/image\(number).png")
            try ImageEngine.encode(image, to: media, ext: "png", quality: 1)

            let scale = min(Double(slideW) / Double(image.width),
                            Double(slideH) / Double(image.height))
            let w = Int(Double(image.width) * scale)
            let h = Int(Double(image.height) * scale)
            let x = (slideW - w) / 2
            let y = (slideH - h) / 2

            let slide = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
            <p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>
            <p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>
            <p:pic><p:nvPicPr><p:cNvPr id="2" name="Page \(number)"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>
            <p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
            <p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
            </p:pic></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
            """
            try slide.write(to: ppt.appendingPathComponent("slides/slide\(number).xml"),
                            atomically: true, encoding: .utf8)

            let rels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image\(number).png"/>
            </Relationships>
            """
            let slideRelDir = ppt.appendingPathComponent("slides/_rels", isDirectory: true)
            try FileManager.default.createDirectory(at: slideRelDir, withIntermediateDirectories: true)
            try rels.write(to: slideRelDir.appendingPathComponent("slide\(number).xml.rels"),
                           atomically: true, encoding: .utf8)

            slideIds += "<p:sldId id=\"\(255 + number)\" r:id=\"rId\(number + 1)\"/>\n"
            slideRels += "<Relationship Id=\"rId\(number + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(number).xml\"/>\n"
            contentOverrides += "<Override PartName=\"/ppt/slides/slide\(number).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>\n"
        }

        let presentation = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
        <p:sldIdLst>\(slideIds)</p:sldIdLst>
        <p:sldSz cx="\(slideW)" cy="\(slideH)"/><p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
        """
        try presentation.write(to: ppt.appendingPathComponent("presentation.xml"),
                               atomically: true, encoding: .utf8)

        let presentationRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
        \(slideRels)</Relationships>
        """
        let pptRels = ppt.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: pptRels, withIntermediateDirectories: true)
        try presentationRels.write(to: pptRels.appendingPathComponent("presentation.xml.rels"),
                                   atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(
            at: ppt.appendingPathComponent("slideMasters/_rels", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: ppt.appendingPathComponent("slideLayouts/_rels", isDirectory: true),
            withIntermediateDirectories: true)
        try slideMaster.write(to: ppt.appendingPathComponent("slideMasters/slideMaster1.xml"),
                              atomically: true, encoding: .utf8)
        try masterRels.write(to: ppt.appendingPathComponent("slideMasters/_rels/slideMaster1.xml.rels"),
                             atomically: true, encoding: .utf8)
        try slideLayout.write(to: ppt.appendingPathComponent("slideLayouts/slideLayout1.xml"),
                              atomically: true, encoding: .utf8)
        try layoutRels.write(to: ppt.appendingPathComponent("slideLayouts/_rels/slideLayout1.xml.rels"),
                             atomically: true, encoding: .utf8)
        try theme.write(to: ppt.appendingPathComponent("theme/theme1.xml"),
                        atomically: true, encoding: .utf8)

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Default Extension="png" ContentType="image/png"/>
        <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
        <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
        <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
        <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        \(contentOverrides)</Types>
        """
        try contentTypes.write(to: dir.appendingPathComponent("[Content_Types].xml"),
                               atomically: true, encoding: .utf8)

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
        </Relationships>
        """
        let rootRelsDir = dir.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: rootRelsDir, withIntermediateDirectories: true)
        try rootRels.write(to: rootRelsDir.appendingPathComponent(".rels"),
                           atomically: true, encoding: .utf8)

        try ZipUtil.zipDirectory(dir, to: out)
    }

    private static let slideLayout = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
    <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
    <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
    </p:sldLayout>
    """

    private static let layoutRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
    </Relationships>
    """

    private static let slideMaster = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
    <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
    <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
    <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
    <p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz="3200"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:otherStyle></p:txStyles>
    </p:sldMaster>
    """

    private static let masterRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
    </Relationships>
    """

    private static let theme = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Zest">
    <a:themeElements>
    <a:clrScheme name="Zest">
    <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
    <a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>
    <a:accent1><a:srgbClr val="FF8A3D"/></a:accent1><a:accent2><a:srgbClr val="4472C4"/></a:accent2>
    <a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4>
    <a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6>
    <a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Zest"><a:majorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Zest">
    <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
    <a:lnStyleLst>
    <a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
    <a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
    <a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
    </a:lnStyleLst>
    <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>
    <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>
    </a:fmtScheme>
    </a:themeElements>
    </a:theme>
    """
}

// MARK: - XLSX

enum XlsxWriter {
    static func write(rows: [[String]], sheetName: String = "Sheet1", to out: URL) throws {
        let dir = Temp.dir()
        let xl = dir.appendingPathComponent("xl", isDirectory: true)
        try FileManager.default.createDirectory(at: xl.appendingPathComponent("worksheets"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xl.appendingPathComponent("_rels"),
                                                withIntermediateDirectories: true)

        var sheet = ""
        for (r, row) in rows.enumerated() {
            var cells = ""
            for (c, value) in row.enumerated() where !value.isEmpty {
                let ref = "\(columnName(c))\(r + 1)"
                if let number = Double(value), value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil {
                    cells += "<c r=\"\(ref)\"><v>\(number)</v></c>"
                } else {
                    cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(TextTools.escapeXML(value))</t></is></c>"
                }
            }
            sheet += "<row r=\"\(r + 1)\">\(cells)</row>\n"
        }

        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(sheet)</sheetData></worksheet>
        """
        try sheetXML.write(to: xl.appendingPathComponent("worksheets/sheet1.xml"),
                           atomically: true, encoding: .utf8)

        let safeName = sheetName.replacingOccurrences(of: "[\\[\\]:*?/\\\\]",
                                                      with: " ", options: .regularExpression)
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(TextTools.escapeXML(safeName.prefix(31).description))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
        try workbook.write(to: xl.appendingPathComponent("workbook.xml"),
                           atomically: true, encoding: .utf8)

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        try workbookRels.write(to: xl.appendingPathComponent("_rels/workbook.xml.rels"),
                               atomically: true, encoding: .utf8)

        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """
        try styles.write(to: xl.appendingPathComponent("styles.xml"),
                         atomically: true, encoding: .utf8)

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
        try contentTypes.write(to: dir.appendingPathComponent("[Content_Types].xml"),
                               atomically: true, encoding: .utf8)

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let rootRels = dir.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: rootRels, withIntermediateDirectories: true)
        try rels.write(to: rootRels.appendingPathComponent(".rels"),
                       atomically: true, encoding: .utf8)

        try ZipUtil.zipDirectory(dir, to: out)
    }

    static func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }
}

// MARK: - ODS

enum OdsWriter {
    static func write(rows: [[String]], to out: URL) throws {
        let dir = Temp.dir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("META-INF"),
                                                withIntermediateDirectories: true)
        try "application/vnd.oasis.opendocument.spreadsheet"
            .write(to: dir.appendingPathComponent("mimetype"),
                   atomically: true, encoding: .utf8)

        var body = ""
        for row in rows {
            var cells = ""
            for value in row {
                if let number = Double(value), !value.isEmpty {
                    cells += "<table:table-cell office:value-type=\"float\" office:value=\"\(number)\"><text:p>\(value)</text:p></table:table-cell>"
                } else {
                    cells += "<table:table-cell office:value-type=\"string\"><text:p>\(TextTools.escapeXML(value))</text:p></table:table-cell>"
                }
            }
            body += "<table:table-row>\(cells)</table:table-row>\n"
        }

        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
        <office:body><office:spreadsheet><table:table table:name="Sheet1">
        \(body)</table:table></office:spreadsheet></office:body></office:document-content>
        """
        try content.write(to: dir.appendingPathComponent("content.xml"),
                          atomically: true, encoding: .utf8)

        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
        <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
        <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """
        try manifest.write(to: dir.appendingPathComponent("META-INF/manifest.xml"),
                           atomically: true, encoding: .utf8)

        try? FileManager.default.removeItem(at: out)
        try Shell.run("/usr/bin/zip", ["-X0", out.path, "mimetype"], cwd: dir)
        try Shell.run("/usr/bin/zip", ["-Xr9", out.path, "META-INF", "content.xml"], cwd: dir)
    }
}

// MARK: - Sheets

enum SheetReader {
    static func rows(_ url: URL) throws -> [[String]] {
        switch url.pathExtension.lowercased() {
        case "csv":
            return parseDelimited(try String(contentsOf: url, encoding: .utf8), separator: ",")
        case "tsv":
            return parseDelimited(try String(contentsOf: url, encoding: .utf8), separator: "\t")
        case "xlsx":
            return try xlsxRows(url)
        case "ods":
            return try odsRows(url)
        case "xls":
            guard let soffice = ToolFinder.soffice else {
                throw ZestError("Legacy .xls needs LibreOffice (soffice) or an export to .xlsx")
            }
            let dir = Temp.dir()
            try Shell.run(soffice, ["--headless", "--convert-to", "xlsx",
                                    "--outdir", dir.path, url.path])
            let converted = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".xlsx")
            return try xlsxRows(converted)
        default:
            throw ZestError("Unsupported spreadsheet: .\(url.pathExtension)")
        }
    }

    static func xlsxRows(_ url: URL) throws -> [[String]] {
        let dir = Temp.dir()
        try ZipUtil.unzip(url, to: dir)
        let sharedURL = dir.appendingPathComponent("xl/sharedStrings.xml")
        var shared: [String] = []
        if let xml = try? String(contentsOf: sharedURL, encoding: .utf8) {
            shared = matches("<si>(.*?)</si>", in: xml).map { si in
                matches("<t[^>]*>(.*?)</t>", in: si)
                    .map { TextTools.unescapeXML($0) }.joined()
            }
        }
        let sheetDir = dir.appendingPathComponent("xl/worksheets")
        let sheets = ((try? FileManager.default.contentsOfDirectory(at: sheetDir,
                        includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix("sheet") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = sheets.first,
              let xml = try? String(contentsOf: first, encoding: .utf8) else { return [] }

        var rows: [[String]] = []
        for rowXML in matches("<row[^>]*>(.*?)</row>", in: xml) {
            var values: [String] = []
            for cell in matches("<c[^>]*>.*?</c>|<c[^>]*/>", in: rowXML) {
                let ref = attribute("r", in: cell) ?? ""
                let type = attribute("t", in: cell) ?? ""
                let column = columnIndex(ref) ?? values.count
                var value = ""
                if let raw = firstMatch("<v[^>]*>(.*?)</v>", in: cell) {
                    value = TextTools.unescapeXML(raw)
                } else if let inline = firstMatch("<t[^>]*>(.*?)</t>", in: cell) {
                    value = TextTools.unescapeXML(inline)
                }
                if type == "s", let index = Int(value), index < shared.count {
                    value = shared[index]
                }
                while values.count < column { values.append("") }
                if values.count == column { values.append(value) } else { values[column] = value }
            }
            rows.append(values)
        }
        return rows
    }

    static func odsRows(_ url: URL) throws -> [[String]] {
        let dir = Temp.dir()
        try ZipUtil.unzip(url, to: dir)
        guard let xml = try? String(contentsOf: dir.appendingPathComponent("content.xml"),
                                    encoding: .utf8) else { return [] }
        var rows: [[String]] = []
        for rowXML in matches("<table:table-row.*?</table:table-row>", in: xml) {
            var values: [String] = []
            for cell in matches("<table:table-cell.*?</table:table-cell>", in: rowXML) {
                let texts = matches("<text:p[^>]*>(.*?)</text:p>", in: cell)
                    .map { TextTools.unescapeXML($0) }
                    .joined(separator: "\n")
                values.append(texts)
                if let repeated = attribute("table:number-columns-repeated", in: cell),
                   let count = Int(repeated), count > 1, count < 200 {
                    values.append(contentsOf: Array(repeating: "", count: count - 1))
                }
            }
            rows.append(values)
        }
        return rows
    }

    static func encode(_ rows: [[String]], separator: Character) -> String {
        rows.map { row in
            row.map { cell -> String in
                if cell.contains(separator) || cell.contains("\"") || cell.contains("\n") {
                    return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return cell
            }.joined(separator: String(separator))
        }.joined(separator: "\r\n") + "\r\n"
    }

    static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character?

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let ch = next() {
            if inQuotes {
                if ch == "\"" {
                    if let peek = next() {
                        if peek == "\"" { field.append("\"") }
                        else { inQuotes = false; pending = peek }
                    } else { inQuotes = false }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case separator:
                    row.append(field); field = ""
                case "\n":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                case "\r":
                    break
                default:
                    field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        }
        return rows
    }

    // MARK: Helpers

    static func columnIndex(_ ref: String) -> Int? {
        let letters = ref.prefix { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        var value = 0
        for ch in letters.uppercased() {
            guard let ascii = ch.asciiValue else { return nil }
            value = value * 26 + Int(ascii - 65) + 1
        }
        return value - 1
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]*)\"") else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
