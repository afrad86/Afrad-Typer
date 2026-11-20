import Foundation

enum PassageError: LocalizedError {
    case badURL
    case http(Int)
    case noText

    var errorDescription: String? {
        switch self {
        case .badURL: return "That doesn't look like a valid web address."
        case .http(let code): return "The site answered with error \(code). It may block automated reading."
        case .noText: return "Couldn't find readable text on that page (it may need JavaScript or a login). Try \"Paste text\" instead."
        }
    }
}

enum WebExtractor {
    private static func replace(_ s: String, pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }

    static func extract(html: String) -> (title: String, text: String) {
        var title = ""
        if let re = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = html as NSString
            if let m = re.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                title = normalize(decodeEntities(ns.substring(with: m.range(at: 1))))
                title = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        var body = html
        body = replace(body, pattern: "<!--.*?-->", with: " ")
        body = replace(body, pattern: "<(script|style|noscript|nav|header|footer|aside|svg|form|iframe)[^>]*>.*?</\\1>", with: " ")

        // Prefer the <article> or <main> element when the page has one.
        for tag in ["article", "main"] {
            if let re = try? NSRegularExpression(pattern: "<\(tag)[^>]*>(.*?)</\(tag)>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let ns = body as NSString
                let matches = re.matches(in: body, options: [], range: NSRange(location: 0, length: ns.length))
                if !matches.isEmpty {
                    let joined = matches.map { ns.substring(with: $0.range(at: 1)) }.joined(separator: "\n")
                    if joined.count > 400 {
                        body = joined
                        break
                    }
                }
            }
        }

        body = replace(body, pattern: "</(p|div|h[1-6]|li|tr|blockquote|section)>|<br\\s*/?>", with: "\n")
        body = replace(body, pattern: "<[^>]+>", with: " ")
        body = decodeEntities(body)
        body = normalize(body)

        var paragraphs: [String] = []
        for line in body.components(separatedBy: "\n") {
            let collapsed = replace(line, pattern: "\\s+", with: " ").trimmingCharacters(in: .whitespaces)
            if collapsed.count >= 50 && collapsed.contains(" ") {
                paragraphs.append(collapsed)
            }
        }
        var text = paragraphs.joined(separator: " ")
        if text.count > 30000 { text = String(text.prefix(30000)) }
        return (title, text)
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&rsquo;", "'"), ("&lsquo;", "'"), ("&ldquo;", "\""), ("&rdquo;", "\""),
            ("&mdash;", "-"), ("&ndash;", "-"), ("&hellip;", "..."), ("&lt;", "<"), ("&gt;", ">")
        ]
        for (k, v) in named { r = r.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: []) {
            let ns = r as NSString
            let matches = re.matches(in: r, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let code = ns.substring(with: m.range(at: 1))
                var value: UInt32?
                if code.hasPrefix("x") || code.hasPrefix("X") {
                    value = UInt32(code.dropFirst(), radix: 16)
                } else {
                    value = UInt32(code)
                }
                if let v = value, let scalar = Unicode.Scalar(v) {
                    r = (r as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                }
            }
        }
        r = r.replacingOccurrences(of: "&amp;", with: "&")
        return r
    }

    /// Converts typographic characters to plain keyboard characters and drops anything that can't be typed on a standard keyboard.
    static func normalize(_ s: String) -> String {
        let map: [Character: String] = [
            "\u{2019}": "'", "\u{2018}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
            "\u{2013}": "-", "\u{2014}": "-", "\u{2026}": "...", "\u{00A0}": " ",
            "\u{2022}": "-", "\u{2212}": "-"
        ]
        var out = ""
        for ch in s {
            if let m = map[ch] {
                out += m
            } else if ch.isNewline {
                out += "\n"
            } else if let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1, v >= 32, v <= 126 {
                out.append(ch)
            } else if ch == "\t" {
                out += " "
            }
        }
        return out
    }
}

enum PassageChunker {
    /// Splits a passage into lesson-sized pieces at sentence boundaries.
    static func chunks(_ text: String, target: Int = 260) -> [String] {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        var sentences: [String] = []
        var cur = ""
        for ch in clean {
            cur.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                sentences.append(cur)
                cur = ""
            }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { sentences.append(cur) }

        var out: [String] = []
        var buf = ""
        for s in sentences {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            for piece in splitLong(t, max: 380) {
                if buf.isEmpty {
                    buf = piece
                } else if buf.count + 1 + piece.count <= target {
                    buf += " " + piece
                } else {
                    out.append(buf)
                    buf = piece
                }
            }
        }
        if !buf.isEmpty { out.append(buf) }
        return out
    }

    private static func splitLong(_ s: String, max: Int) -> [String] {
        if s.count <= max { return [s] }
        var parts: [String] = []
        var cur = ""
        for word in s.split(separator: " ") {
            if cur.isEmpty {
                cur = String(word)
            } else if cur.count + 1 + word.count <= max {
                cur += " " + word
            } else {
                parts.append(cur)
                cur = String(word)
            }
        }
        if !cur.isEmpty { parts.append(cur) }
        return parts
    }
}
