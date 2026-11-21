import Foundation
import SwiftUI
import CryptoKit

struct BookPart: Codable {
    var title: String
    var text: String
}

struct Book: Codable, Identifiable {
    var id: String
    var title: String
    var author: String
    var level: String
    var parts: [BookPart]
}

/// The built-in story books. They come from books.json inside the app (made by tools/get_books.py).
enum Books {
    static let all: [Book] = {
        guard let url = Bundle.main.url(forResource: "books", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Book].self, from: d) else { return [] }
        return list
    }()

    /// A stable id for each part, so the chosen part is remembered between launches.
    static func uuid(_ book: String, _ index: Int) -> UUID {
        let b = Array(Insecure.MD5.hash(data: Data("book:\(book):\(index)".utf8)))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// Which book and part a passage id belongs to (nil for your own passages).
    static let index: [UUID: (book: Int, part: Int)] = {
        var m: [UUID: (book: Int, part: Int)] = [:]
        for (bi, b) in all.enumerated() {
            for pi in 0..<b.parts.count { m[uuid(b.id, pi)] = (bi, pi) }
        }
        return m
    }()

    static let partList: [Passage] = makeParts()

    static var parts: [Passage] { partList }

    private static func makeParts() -> [Passage] {
        var out: [Passage] = []
        for b in all {
            for (i, p) in b.parts.enumerated() {
                out.append(Passage(id: uuid(b.id, i), title: "\(b.title) \u{2014} \(p.title)", url: "Story", text: p.text))
            }
        }
        return out
    }
}

extension Store {
    /// Your own passages followed by the built-in story parts.
    var allPassages: [Passage] { data.passages + Books.parts }
}

/// Fonts offered for the typing text. All of them ship with macOS and Windows.
enum TypingFont {
    static let all: [(key: String, name: String, hint: String)] = [
        ("mono", "Monospace", "default"), ("sans", "Sans-serif", ""), ("serif", "Serif", ""),
        ("type", "Typewriter", ""), ("comf", "Comfortable", "easy to read")
    ]
    static func name(_ key: String) -> String { all.first(where: { $0.key == key })?.name ?? "Monospace" }
    static func font(_ key: String, size: CGFloat) -> Font {
        switch key {
        case "sans": return .system(size: size)
        case "serif": return .system(size: size, design: .serif)
        case "type": return .custom("Courier New", size: size)
        case "comf": return .custom("Verdana", size: size)
        default: return .system(size: size, design: .monospaced)
        }
    }
    /// A safe average character width (as a share of the font size) for fitting lines.
    static func charWidth(_ key: String) -> CGFloat {
        switch key {
        case "sans": return 0.58
        case "serif": return 0.56
        case "type": return 0.6
        case "comf": return 0.64
        default: return 0.61
        }
    }
}
