import Foundation

/// Works out the user's level from recent sessions.
/// Counted: normal text modes (not symbols or single-spot drills), no warm-ups or replays, very short runs (under ~30 characters) ignored, the rest weighted by length.
/// A lesson or passage repeated on the same day counts once (the best run). Median of the last 30.
/// Accuracy below 95% scales speed down (net speed). Levels have a +/-2 WPM buffer so the tag does not flicker.
enum LevelCalc {
    static let thresholds: [Int] = [100, 80, 60, 40, 0]

    struct Result {
        let wpm: Int
        let accuracy: Double
        let tier: Int        // index into thresholds, after accuracy
        let plainTier: Int   // index from speed only
        let count: Int
    }

    private static let excludedModes: Set<String> = [
        PracticeMode.symbols.rawValue, PracticeMode.weakKeys.rawValue,
        PracticeMode.pairs.rawValue, PracticeMode.slowWords.rawValue
    ]

    static func sessions(_ history: [SessionRecord]) -> [SessionRecord] {
        var out: [SessionRecord] = []
        var seen: [String: Int] = [:]
        let dedupeModes: Set<String> = [PracticeMode.drills.rawValue, PracticeMode.passages.rawValue]
        for r in history.sorted(by: { $0.date < $1.date }) {
            if !r.isCounted || excludedModes.contains(r.mode) || r.characters < 30 { continue }
            if dedupeModes.contains(r.mode) {
                let day = Int(Calendar.current.startOfDay(for: r.date).timeIntervalSince1970)
                let key = "\(day)|\(r.mode)|\(r.detail)"
                if let i = seen[key] {
                    if r.wpm > out[i].wpm { out[i] = r }
                } else {
                    seen[key] = out.count
                    out.append(r)
                }
            } else {
                out.append(r)
            }
        }
        return Array(out.suffix(30))
    }

    static func pickTier(_ v: Double, stored: Int?) -> Int {
        let n = thresholds.count
        if let s = stored, s >= 0, s < n {
            let stay = v >= Double(thresholds[s] - 2) && (s == 0 || v < Double(thresholds[s - 1] + 2))
            if stay { return s }
        }
        return thresholds.firstIndex(where: { v >= Double($0) }) ?? (n - 1)
    }

    static func assess(_ history: [SessionRecord], storedTier: Int?, storedPlain: Int?) -> Result? {
        let last = sessions(history)
        guard last.count >= 10 else { return nil }
        // Longer sessions weigh more (capped), so a 10-word drill barely moves the level.
        func weight(_ r: SessionRecord) -> Double { Double(min(400, r.characters)) }
        let sorted = last.sorted { $0.wpm < $1.wpm }
        let total = sorted.map(weight).reduce(0, +)
        var cum = 0.0
        var med = sorted[sorted.count - 1].wpm
        for r in sorted {
            cum += weight(r)
            if cum >= total / 2 { med = r.wpm; break }
        }
        let acc = last.map { $0.accuracy * weight($0) }.reduce(0, +) / total
        let net = acc >= 95 ? med : med * pow(acc / 95, 2)
        return Result(wpm: Int(med.rounded()), accuracy: acc,
                      tier: pickTier(net, stored: storedTier),
                      plainTier: pickTier(med, stored: storedPlain),
                      count: last.count)
    }

    /// Remembers the tier after each session so the buffer works. Called when a session is saved.
    static func commit(_ store: Store) {
        let s = store.data.settings
        guard let r = assess(store.data.history, storedTier: s.levelTier, storedPlain: s.levelTierPlain) else { return }
        if s.levelTier != r.tier || s.levelTierPlain != r.plainTier {
            store.data.settings.levelTier = r.tier
            store.data.settings.levelTierPlain = r.plainTier
        }
    }
}
