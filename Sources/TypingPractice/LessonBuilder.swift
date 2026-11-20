import Foundation

enum LessonBuilder {
    /// A small deterministic random generator so a mixed order is the same every time for a given source and scope.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// The scoped list of practice items for the chosen source. With "mixed order" the Top-N items are shuffled
    /// in a fixed order, so every lesson is a varied mix instead of lesson 1 being only the most frequent items.
    static func items(_ s: AppSettings) -> [String] {
        var list: [String]
        switch s.source {
        case .trigrams: list = Array(NgramData.drillTrigrams.prefix(s.scope))
        case .tetragrams: list = Array(NgramData.drillTetragrams.prefix(s.scope))
        case .words: list = Array(NgramData.drillWords.prefix(s.scope))
        case .commonWords: list = Array(NgramData.commonWords.prefix(s.scope))
        case .custom:
            return s.customWords
                .split(whereSeparator: { $0.isWhitespace })
                .map { String($0) }
        }
        if s.mixedOrder {
            var seed: UInt64 = 1469598103934665603
            for u in "\(s.source.rawValue)|\(s.scope)".unicodeScalars { seed = (seed ^ UInt64(u.value)) &* 1099511628211 }
            var rng = SeededRNG(state: seed)
            list.shuffle(using: &rng)
        }
        return list
    }

    /// Combination: the lesson's items chained in order, the whole chain repeated `repeats` times.
    /// Repetition: each item repeated `repeats` times back to back.
    static func lessonText(chunk: [String], generator: GeneratorStyle, repeats: Int) -> String {
        guard !chunk.isEmpty else { return "" }
        let r = max(1, repeats)
        switch generator {
        case .repetition:
            return chunk.flatMap { Array(repeating: $0, count: r) }.joined(separator: " ")
        case .combination:
            return (0..<r).flatMap { _ in chunk }.joined(separator: " ")
        }
    }

    /// Randomly capitalises and punctuates words. Each percentage is the chance (0-100) that any given word is affected.
    static func decorate(_ text: String, capitals: Int, punctuation: Int) -> String {
        if capitals <= 0 && punctuation <= 0 { return text }
        let marks: [Character] = [".", ",", ";", ":", "!", "?", "-"]
        var out: [String] = []
        for token in text.split(separator: " ") {
            var t = String(token)
            if capitals > 0, Int.random(in: 1...100) <= capitals, let first = t.first, first.isLowercase {
                t = String(first).uppercased() + String(t.dropFirst())
            }
            if punctuation > 0, Int.random(in: 1...100) <= punctuation, let m = marks.randomElement() {
                t.append(m)
            }
            out.append(t)
        }
        return out.joined(separator: " ")
    }

    private static func pool(_ size: Int, minLength: Int = 1) -> [String] {
        Array(NgramData.words.prefix(max(size, 100))).filter { $0.count >= minLength }
    }

    private static func plainWords(_ size: Int, count: Int = 30) -> String {
        let p = pool(size, minLength: 3)
        return (0..<count).compactMap { _ in p.randomElement() }.joined(separator: " ")
    }

    static func timedText(pool size: Int, count: Int = 350) -> String {
        let p = pool(size)
        var out: [String] = []
        var last = ""
        while out.count < count {
            guard let w = p.randomElement() else { break }
            if w == last { continue }
            out.append(w)
            last = w
        }
        return out.joined(separator: " ")
    }

    // MARK: Weak keys

    static func weakScore(_ st: KeyStat) -> Double {
        guard st.attempts >= 5 else { return 0 }
        let slow = st.avgMs > 0 ? max(0, min((st.avgMs - 250) / 750, 1)) : 0
        return st.missRate * 3 + slow * 0.5
    }

    static func weakKeys(_ stats: [String: KeyStat], limit: Int = 5) -> [String] {
        let rows: [(String, Double)] = stats
            .filter { $0.key.count == 1 && ($0.key.first?.isLetter ?? false) && $0.value.attempts >= 5 }
            .map { ($0.key, weakScore($0.value)) }
        return rows
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    static func weakKeyText(stats: [String: KeyStat], pool size: Int, count: Int = 28) -> (text: String, keys: [String]) {
        let keys = weakKeys(stats)
        let words = pool(size, minLength: 3)
        if keys.isEmpty {
            return (plainWords(size, count: count), [])
        }
        var weight: [Character: Double] = [:]
        for (i, k) in keys.enumerated() {
            if let ch = k.first { weight[ch] = Double(keys.count - i) }
        }
        let scored: [(String, Double)] = words.map { w in
            var s = 0.0
            for ch in w { s += weight[ch] ?? 0 }
            return (w, s / Double(w.count).squareRoot())
        }
        let top = scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(80)
            .map { $0.0 }
        if top.isEmpty {
            return (plainWords(size, count: count), keys)
        }
        let chosen = (0..<count).compactMap { _ in top.randomElement() }
        return (chosen.joined(separator: " "), keys)
    }

    // MARK: Slow letter pairs

    static func pairScore(_ st: KeyStat, minAttempts: Int = 3) -> Double {
        guard st.attempts >= minAttempts else { return 0 }
        let slow = st.avgMs > 0 ? max(0, min((st.avgMs - 180) / 600, 1)) : 0
        return st.missRate * 3 + slow
    }

    static func slowPairs(_ stats: [String: KeyStat], limit: Int = 6) -> [String] {
        let rows: [(String, Double)] = stats.map { ($0.key, pairScore($0.value)) }
        return rows
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    static func pairText(stats: [String: KeyStat], pool size: Int, count: Int = 30) -> (text: String, pairs: [String]) {
        let pairs = slowPairs(stats)
        if pairs.isEmpty { return (plainWords(size, count: count), []) }
        var weight: [String: Double] = [:]
        for (i, p) in pairs.enumerated() { weight[p] = Double(pairs.count - i) }
        let words = pool(size, minLength: 3)
        let scored: [(String, Double)] = words.map { w in
            let chars = Array(w)
            var s = 0.0
            if chars.count >= 2 {
                for i in 0..<(chars.count - 1) {
                    let pair = String(chars[i...(i + 1)])
                    s += weight[pair] ?? 0
                }
            }
            return (w, s)
        }
        let top = scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(60)
            .map { $0.0 }
        if top.isEmpty { return (plainWords(size, count: count), pairs) }
        var tokens: [String] = []
        for p in pairs { tokens.append(contentsOf: [p, p, p]) }
        for _ in 0..<max(8, count - pairs.count * 3) {
            if let w = top.randomElement() { tokens.append(w) }
        }
        return (tokens.joined(separator: " "), pairs)
    }

    // MARK: Slow words

    static func wordScore(_ st: KeyStat, baseline: Double) -> Double {
        guard st.attempts >= 2, st.timedCount >= 3 else { return 0 }
        let rel = baseline > 0 ? max(0, st.avgMs / baseline - 1) : 0
        return rel + st.missRate * 3
    }

    static func slowWords(_ stats: [String: KeyStat], baseline: Double, limit: Int = 8) -> [String] {
        let rows: [(String, Double)] = stats.map { ($0.key, wordScore($0.value, baseline: baseline)) }
        return rows
            .filter { $0.1 > 0.1 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    static func slowWordText(stats: [String: KeyStat], baseline: Double, pool size: Int, count: Int = 24) -> (text: String, words: [String]) {
        let words = slowWords(stats, baseline: baseline)
        if words.isEmpty {
            let longer = pool(size, minLength: 6)
            let plain = (0..<count).compactMap { _ in longer.randomElement() }
            return (plain.joined(separator: " "), [])
        }
        var tokens: [String] = []
        var last = ""
        for _ in 0..<max(1, count / max(1, words.count)) {
            var round = words.shuffled()
            if round.count > 1, round.first == last {
                round.swapAt(0, round.count - 1)
            }
            tokens.append(contentsOf: round)
            last = round.last ?? ""
        }
        return (tokens.joined(separator: " "), words)
    }

    /// Weak-spot practice for trigram/tetragram lessons: pieces of exactly `n` letters that contain your weak keys,
    /// slow pairs, or come from your slow words. Never whole words.
    static func ngramBoost(n: Int, list: [String], keys: [String], pairs: [String], words: [String], count: Int) -> [String] {
        var pool: [String] = []
        var seen = Set<String>()
        func add(_ g: String) {
            if g.count == n, !seen.contains(g) { seen.insert(g); pool.append(g) }
        }
        let top = Array(list.prefix(1000))
        for g in top {
            for k in keys where g.contains(k) { add(g) }
            for p in pairs where g.contains(p) { add(g) }
        }
        for w in words {
            let chars = Array(w)
            if chars.count >= n {
                for i in 0...(chars.count - n) { add(String(chars[i..<(i + n)])) }
            }
        }
        guard !pool.isEmpty else { return [] }
        var out: [String] = []
        var last = ""
        var bag: [String] = []
        while out.count < max(3, count) {
            if bag.isEmpty { bag = pool.shuffled() }
            let g = bag.removeLast()
            if g == last && pool.count > 1 { continue }
            out.append(g)
            last = g
        }
        return out
    }

    // MARK: Numbers and symbols

    static func symbolsText(pool size: Int, count: Int = 36) -> String {
        let words = pool(size, minLength: 3)
        func w() -> String { words.randomElement() ?? "text" }
        func n(_ r: ClosedRange<Int>) -> Int { Int.random(in: r) }
        var tokens: [String] = []
        for _ in 0..<count {
            switch Int.random(in: 0..<14) {
            case 0: tokens.append("\(n(1...9999))")
            case 1: tokens.append("\(n(1...99)).\(n(1...99))")
            case 2: tokens.append("$\(n(1...999))")
            case 3: tokens.append("\(n(1...100))%")
            case 4: tokens.append("\(n(1...28))/\(n(1...12))")
            case 5:
                let mm = String(format: "%02d", n(0...59))
                tokens.append("\(n(1...12)):\(mm)")
            case 6: tokens.append("(\(w()))")
            case 7: tokens.append("\"\(w())\"")
            case 8: tokens.append("#\(w())")
            case 9: tokens.append("@\(w())")
            case 10:
                let a = n(1...50)
                let b = n(1...50)
                tokens.append("\(a)+\(b)=\(a + b)")
            case 11: tokens.append("\(w())&\(w())")
            case 12: tokens.append("\(w())/\(w())")
            default: tokens.append("\(w())-\(n(1...99))")
            }
        }
        return tokens.joined(separator: " ")
    }
}
