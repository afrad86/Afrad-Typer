import Foundation

/// Practice data. `words` is the everyday word list (see WordList.swift), ordered by real-world frequency.
/// The n-gram lists are derived from it (weighted by 1/rank), so "Top 50/100/…" follows English frequency.
enum NgramData {
    static let words: [String] = WordList.raw
        .split(whereSeparator: { $0 == " " || $0 == "\n" })
        .map { String($0) }

    /// Drill lists: the Ngram Type website's Top-200 lists first (same order), then our own list continues
    /// beyond 200, so the bigger scopes (500, 1000, ...) still work.
    private static func extend(_ site: [String], with more: [String]) -> [String] {
        var seen = Set(site)
        var out = site
        for w in more where !seen.contains(w) {
            seen.insert(w)
            out.append(w)
        }
        return out
    }

    static let drillWords: [String] = extend(SiteData.list(SiteData.wordsRaw), with: words)
    static let drillTrigrams: [String] = extend(SiteData.list(SiteData.trigramsRaw), with: trigrams)
    static let drillTetragrams: [String] = extend(SiteData.list(SiteData.tetragramsRaw), with: tetragrams)

    /// Real everyday words only: four or more letters, so "Top 50" is words like "that", "with", "have", "people".
    static let commonWords: [String] = drillWords.filter { $0.count >= 4 }

    static let trigrams: [String] = compute(3)
    static let tetragrams: [String] = compute(4)

    private static func compute(_ n: Int) -> [String] {
        var weights: [String: Double] = [:]
        for (rank, w) in words.enumerated() {
            let chars = Array(w)
            guard chars.count >= n else { continue }
            let weight = 1.0 / Double(rank + 1)
            for i in 0...(chars.count - n) {
                let g = String(chars[i..<(i + n)])
                weights[g, default: 0] += weight
            }
        }
        let sorted = weights.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }
        return sorted.prefix(1000).map { $0.key }
    }
}
