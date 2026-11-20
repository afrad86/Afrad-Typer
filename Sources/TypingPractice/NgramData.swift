import Foundation

/// Practice data. `words` is the everyday word list (see WordList.swift), ordered by real-world frequency.
/// The n-gram lists are the most common real trigrams/tetragrams of everyday English (RealNgrams.swift).
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

    /// Real, commonly used groups only (see RealNgrams.swift), ranked by how often they occur in everyday English.
    static let trigrams: [String] = RealNgrams.trigrams
    static let tetragrams: [String] = RealNgrams.tetragrams
}
