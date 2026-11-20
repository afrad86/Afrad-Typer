import SwiftUI
import AppKit

enum KeyEvent {
    case char(Character)
    case backspace
    case enter
    case escape
    case tab
}

enum CharState {
    case untyped
    case correct
    case wrong
}

struct SessionResult {
    var wpm: Double
    var rawWPM: Double
    var accuracy: Double
    var consistency: Double   // 0 means not enough data
    var seconds: Double
    var characters: Int
    var passed: Bool?
    var timedOut: Bool
    var stage: Bool = false
    var note: String? = nil
}

final class PracticeController: ObservableObject {
    let store: Store

    @Published var target: [Character] = []
    @Published var states: [CharState] = []
    @Published var pos = 0
    @Published var elapsed: TimeInterval = 0
    @Published var started = false
    @Published var result: SessionResult? = nil
    @Published var lessonLabel = ""
    @Published var infoLine = ""
    @Published var coachLine = ""
    @Published var avgWPM: Double = 0
    @Published var focusMode = false {
        didSet {
            if store.data.settings.focusMode != focusMode { store.data.settings.focusMode = focusMode }
            if !focusMode { showOptions = false }
        }
    }
    @Published var showOptions = false
    @Published var breakDue = false
    @Published var unlockMessage: String? = nil
    @Published var settingsOpen = false
    @Published var lineChars = 56
    @Published var missedWords: [String] = []
    private(set) var isReplay = false
    private(set) var isWarmup = false
    private var warmupPace = 30
    private var replayWords: [String]? = nil
    private var activeSeconds: Double = 0

    var active = false
    private(set) var currentMode: PracticeMode = .drills
    private(set) var timeLimit: TimeInterval = 0
    private(set) var lines: [Range<Int>] = []
    private(set) var correctCount = 0
    private(set) var totalKeys = 0
    private(set) var correctKeys = 0
    private(set) var lessonIndex = 0
    private(set) var lessonCount = 0

    private var currentKey: String? = nil
    private var detailText = ""
    private var startDate: Date?
    private var lastKeyTime: Date?
    private var keyStatsSession: [String: KeyStat] = [:]
    private var pairSession: [String: KeyStat] = [:]
    private var wordSession: [String: KeyStat] = [:]
    private var intervals: [Double] = []
    private var prevExpected: Character? = nil
    private var lessonWPMs: [Double] = []
    private var monitor: Any?
    private var timer: Timer?

    // Word tracking
    private var wordRanges: [Range<Int>] = []
    // Weak-spot words mixed into a lesson: they are not counted against the lesson's pass mark.
    private var pendingBoostFlags: [Bool]? = nil
    private var boostMask: [Bool] = []
    private var boostKeys = 0
    private var boostCorrect = 0
    private var wordIndexAt: [Int] = []
    private var curWord = -1
    private var curSum = 0.0
    private var curCount = 0
    private var curErr = false

    // Smart coach
    private var smartPlan: [PracticeMode] = []
    private var smartStep = 0

    init(store: Store) {
        self.store = store
        self.focusMode = store.data.settings.focusMode
        if store.data.settings.mode == .stages { store.data.settings.mode = .drills }
    }

    /// Stops listening to the keyboard (used when switching user).
    func shutdown() {
        active = false
        timer?.invalidate()
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    // MARK: Derived values for the UI

    var canNavigateLessons: Bool { lessonCount > 1 && currentKey != nil }

    var showThreshold: Bool {
        currentMode == .drills || currentMode == .passages
    }

    var liveWPM: Double {
        guard started else { return 0 }
        let minutes = max(elapsed, 1) / 60
        return Double(correctCount) / 5 / minutes
    }

    var liveAccuracy: Double {
        totalKeys == 0 ? 100 : Double(correctKeys) / Double(totalKeys) * 100
    }

    /// In a stage qualifier the pace caret always shows the stage speed.
    private var effectivePace: Int {
        if isWarmup { return warmupPace }
        return currentMode == .stages && !isReplay ? store.data.settings.stageSelected : store.data.settings.paceWPM
    }

    /// Position of the pace caret (the "ghost" typing at the chosen WPM), if enabled.
    var paceIndex: Int? {
        let wpm = effectivePace
        guard wpm > 0, started, result == nil, !target.isEmpty else { return nil }
        let chars = Double(wpm) * 5.0 / 60.0 * elapsed
        return min(target.count - 1, Int(chars))
    }

    /// Characters ahead (+) or behind (-) of the pace caret.
    var paceDelta: Int? {
        guard let p = paceIndex else { return nil }
        return pos - p
    }

    var visibleLines: [Range<Int>] {
        guard !lines.isEmpty else { return [] }
        let cur = lines.firstIndex(where: { $0.contains(pos) }) ?? (lines.count - 1)
        let lo = max(0, cur - 1)
        let hi = min(lines.count - 1, cur + max(1, store.data.settings.linesShown - 2))
        return Array(lines[lo...hi])
    }

    /// Words hidden from view as a speed exercise: the next one or two words after the one you are typing.
    private func hiddenWords() -> ClosedRange<Int>? {
        let n = store.data.settings.hideAhead
        guard n > 0, currentMode != .stages, !wordRanges.isEmpty, result == nil else { return nil }
        var cur = pos < wordIndexAt.count ? wordIndexAt[pos] : -1
        if cur < 0 { cur = wordRanges.firstIndex(where: { $0.lowerBound > pos }) ?? wordRanges.count }
        return (cur + 1)...(cur + n)
    }

    func attributed(_ r: Range<Int>) -> AttributedString {
        let ghost = paceIndex
        let hidden = hiddenWords()
        var out = AttributedString()
        for i in r where i < target.count && i < states.count {
            var shown = String(target[i])
            if let h = hidden, i > pos, i < wordIndexAt.count, wordIndexAt[i] >= 0, h.contains(wordIndexAt[i]) {
                shown = "•"
            }
            var piece = AttributedString(shown)
            switch states[i] {
            case .untyped:
                piece.foregroundColor = Color.secondary
            case .correct:
                piece.foregroundColor = Color(nsColor: .systemGreen)
            case .wrong:
                piece.foregroundColor = Color(nsColor: .systemRed)
                piece.backgroundColor = Color(nsColor: .systemRed).opacity(0.25)
            }
            if let g = ghost, g == i {
                piece.backgroundColor = Color.orange.opacity(0.4)
            }
            if i == pos && result == nil {
                piece.backgroundColor = Color.accentColor.opacity(0.35)
            }
            out.append(piece)
        }
        return out
    }

    // MARK: Smart coach

    /// Looks at your keys, letter pairs and whole words, and lists the weak areas worst-first, then a timed test.
    private func computeSmartPlan() -> [PracticeMode] {
        let keyTop = store.keyStats(last: 20).values.map { LessonBuilder.weakScore($0) }.max() ?? 0
        let pairTop = store.pairStats(last: 20).values.map { LessonBuilder.pairScore($0) }.max() ?? 0
        let base = store.baselineMs(last: 20)
        let wordTop = store.wordStats(last: 20).values.map { LessonBuilder.wordScore($0, baseline: base) }.max() ?? 0
        var ranked: [(PracticeMode, Double)] = [(.weakKeys, keyTop), (.pairs, pairTop), (.slowWords, wordTop)]
        ranked = ranked.filter { $0.1 > 0.15 }.sorted { $0.1 > $1.1 }
        var plan = ranked.map { $0.0 }
        if plan.isEmpty { plan = [.drills] }
        plan.append(.timed)
        return plan
    }

    // MARK: Built-in assessment

    /// Looks at your history and builds extra words for your weakest keys, slowest pairs and slowest words.
    /// Returns nil until there is enough data.
    private func adaptiveBoost(settings s: AppSettings, baseWords: Int, ngram: Int? = nil) -> (tokens: [String], summary: String)? {
        // Only your most recent sessions count, so a weakness you have fixed drops out by itself
        // and new ones take its place.
        let window = 20
        let keyStats = store.keyStats(last: window)
        let pairStats = store.pairStats(last: window)
        let wordStats = store.wordStats(last: window)
        let baseline = store.baselineMs(last: window)
        let keys = LessonBuilder.weakKeys(keyStats, limit: 4)
        let pairs = LessonBuilder.slowPairs(pairStats, limit: 4)
        let words = LessonBuilder.slowWords(wordStats, baseline: baseline, limit: 6)
        var groups: [String] = []
        if !keys.isEmpty { groups.append("keys") }
        if !pairs.isEmpty { groups.append("pairs") }
        if !words.isEmpty { groups.append("words") }
        guard !groups.isEmpty else { return nil }

        // The share adjusts itself: more weak spots or lower recent accuracy means more extra practice.
        let flagged = keys.count + pairs.count + words.count
        let recent = store.data.history.suffix(10)
        let recentAcc = recent.isEmpty ? 100 : recent.map { $0.accuracy }.reduce(0, +) / Double(recent.count)
        var share = 0.15 + 0.04 * Double(flagged)
        if recentAcc < 94 { share += 0.10 }
        share = min(0.6, share)
        let total = max(9, Int((Double(baseWords) * share / (1 - share)).rounded()))
        let each = max(3, total / groups.count)
        if let n = ngram {
            // Trigram / tetragram lessons: the extra practice must be pieces of the same size,
            // never whole words.
            let all = n == 3 ? NgramData.drillTrigrams : NgramData.drillTetragrams
            let tokens = LessonBuilder.ngramBoost(n: n, list: all, keys: keys, pairs: pairs, words: words, count: total)
            guard !tokens.isEmpty else { return nil }
            var sm: [String] = []
            if !keys.isEmpty { sm.append("keys " + keys.map { $0.uppercased() }.joined(separator: " ")) }
            if !pairs.isEmpty { sm.append("pairs " + pairs.map { $0.uppercased() }.joined(separator: " ")) }
            if !words.isEmpty { sm.append("words " + words.joined(separator: " ")) }
            let pct = Int((share * 100).rounded())
            return (tokens, sm.joined(separator: "  ·  ") + "  (\(pct)% extra, from your last \(window) sessions)")
        }
        var parts: [String] = []
        var summary: [String] = []
        if !keys.isEmpty {
            let b = LessonBuilder.weakKeyText(stats: keyStats, pool: s.wordPool, count: each)
            parts.append(b.text)
            summary.append("keys " + b.keys.map { $0.uppercased() }.joined(separator: " "))
        }
        if !pairs.isEmpty {
            let b = LessonBuilder.pairText(stats: pairStats, pool: s.wordPool, count: each)
            parts.append(b.text)
            summary.append("pairs " + b.pairs.map { $0.uppercased() }.joined(separator: " "))
        }
        if !words.isEmpty {
            let b = LessonBuilder.slowWordText(stats: wordStats, baseline: baseline, pool: s.wordPool, count: each)
            parts.append(b.text)
            summary.append("words " + b.words.joined(separator: " "))
        }
        let tokens = parts.joined(separator: " ").split(separator: " ").map { String($0) }.shuffled()
        let pct = Int((share * 100).rounded())
        return tokens.isEmpty ? nil : (tokens, summary.joined(separator: "  ·  ") + "  (\(pct)% extra, from your last \(window) sessions)")
    }

    /// Spreads the extra weak-spot words evenly through the lesson instead of adding them at the end.
    /// Each token carries a flag saying whether it is a weak-spot word.
    static func interleave(_ base: [(String, Bool)], _ extra: [(String, Bool)]) -> [(String, Bool)] {
        guard !extra.isEmpty, !base.isEmpty else { return base + extra }
        var out: [(String, Bool)] = []
        let step = Double(base.count) / Double(extra.count)
        var next = step / 2
        var e = 0
        for (i, t) in base.enumerated() {
            out.append(t)
            while e < extra.count, Double(i + 1) >= next {
                out.append(extra[e])
                e += 1
                next += step
            }
        }
        while e < extra.count {
            out.append(extra[e])
            e += 1
        }
        return out
    }

    // MARK: Session setup

    func newSession() {
        timer?.invalidate()
        timer = nil
        started = false
        startDate = nil
        elapsed = 0
        result = nil
        pos = 0
        correctCount = 0
        totalKeys = 0
        correctKeys = 0
        lastKeyTime = nil
        keyStatsSession = [:]
        pairSession = [:]
        wordSession = [:]
        intervals = []
        prevExpected = nil
        resetWordTracking()
        currentKey = nil
        lessonIndex = 0
        lessonCount = 0
        timeLimit = 0
        detailText = ""
        coachLine = ""
        missedWords = []
        pendingBoostFlags = nil
        boostKeys = 0
        boostCorrect = 0
        isWarmup = false
        isReplay = false
        let replay = replayWords
        replayWords = nil

        let s = store.data.settings
        var mode = s.mode
        if s.mode == .smart {
            if smartPlan.isEmpty || smartStep >= smartPlan.count {
                smartPlan = computeSmartPlan()
                smartStep = 0
            }
            mode = smartPlan[smartStep]
        } else {
            smartPlan = []
            smartStep = 0
        }
        currentMode = mode

        var text = ""

        switch mode {
        case .smart:
            break

        case .drills:
            let items = LessonBuilder.items(s)
            if items.isEmpty {
                lessonLabel = "Add some custom words"
                infoLine = ""
            } else {
                let per = max(1, s.itemsPerLesson)
                let count = (items.count + per - 1) / per
                let key = "drill|\(s.source.rawValue)|\(s.scope)|\(s.generator.rawValue)|\(per)"
                var idx = s.lessonByKey[key] ?? 0
                if idx < 0 || idx >= count { idx = 0 }
                lessonIndex = idx
                lessonCount = count
                currentKey = key
                let chunk = Array(items[(idx * per)..<min(items.count, (idx + 1) * per)])
                text = LessonBuilder.lessonText(chunk: chunk, generator: s.generator, repeats: s.repetition)
                lessonLabel = "Lesson \(idx + 1) / \(count)"
                infoLine = chunk.joined(separator: "    ")
                let scopeText = s.source == .custom ? "" : " top \(s.scope)"
                detailText = "\(s.source.rawValue)\(scopeText) · \(s.generator.rawValue) \(per)×\(s.repetition) · lesson \(idx + 1)"

                // Built-in assessment: the app finds your weak keys, slow pairs and slow words and adds
                // extra practice on them to every lesson, automatically.
                if s.autoFocus, let boost = adaptiveBoost(settings: s, baseWords: chunk.count * max(1, s.repetition), ngram: s.source == .trigrams ? 3 : (s.source == .tetragrams ? 4 : nil)) {
                    let baseTokens = text.split(separator: " ").map { String($0) }
                    let mixed = PracticeController.interleave(baseTokens.map { ($0, false) }, boost.tokens.map { ($0, true) })
                    text = mixed.map { $0.0 }.joined(separator: " ")
                    pendingBoostFlags = mixed.map { $0.1 }
                    infoLine += "\nAuto-focus: " + boost.summary
                    detailText += " · auto-focus"
                }
            }

        case .timed:
            timeLimit = TimeInterval(s.timedSeconds)
            text = LessonBuilder.timedText(pool: s.wordPool)
            lessonLabel = "\(s.timedSeconds)-second test"
            infoLine = "Everyday words from the top \(s.wordPool). Type as much as you can before time runs out."
            detailText = "\(s.timedSeconds) s test"

        case .passages:
            let list = store.data.passages
            if let p = list.first(where: { $0.id == s.selectedPassage }) ?? list.first {
                let chunks = PassageChunker.chunks(p.text, target: max(120, s.wordCount * 6))
                if chunks.isEmpty {
                    lessonLabel = "This passage is empty"
                } else {
                    let key = "passage|\(p.id.uuidString)"
                    var idx = s.lessonByKey[key] ?? 0
                    if idx < 0 || idx >= chunks.count { idx = 0 }
                    lessonIndex = idx
                    lessonCount = chunks.count
                    currentKey = key
                    text = chunks[idx]
                    let shortTitle = p.title.count > 42 ? String(p.title.prefix(42)) + "…" : p.title
                    lessonLabel = "\(shortTitle) — part \(idx + 1) / \(chunks.count)"
                    infoLine = ""
                    detailText = "\(shortTitle) · part \(idx + 1)"
                }
            } else {
                lessonLabel = "No passages yet — add one in the Library"
            }

        case .weakKeys:
            let built = LessonBuilder.weakKeyText(stats: store.keyStats(last: 20), pool: s.wordPool, count: s.wordCount)
            text = built.text
            lessonLabel = "Weak-key drill"
            if built.keys.isEmpty {
                infoLine = "Not enough data yet — practise a few lessons first. Using common words for now."
                detailText = "Weak keys (no data yet)"
            } else {
                infoLine = "Focusing on: " + built.keys.joined(separator: "   ")
                detailText = "Weak keys: " + built.keys.joined(separator: " ")
            }

        case .pairs:
            let built = LessonBuilder.pairText(stats: store.pairStats(last: 20), pool: s.wordPool, count: s.wordCount)
            text = built.text
            lessonLabel = "Slow-pair drill"
            if built.pairs.isEmpty {
                infoLine = "Not enough pair data yet — practise a few lessons first. Using common words for now."
                detailText = "Slow pairs (no data yet)"
            } else {
                let shown = built.pairs.map { $0.uppercased() }
                infoLine = "Focusing on: " + shown.joined(separator: "   ")
                detailText = "Slow pairs: " + shown.joined(separator: " ")
            }

        case .slowWords:
            let built = LessonBuilder.slowWordText(stats: store.wordStats(last: 20), baseline: store.baselineMs(last: 20), pool: s.wordPool, count: s.wordCount)
            text = built.text
            lessonLabel = "Slow-word drill"
            if built.words.isEmpty {
                infoLine = "Not enough word data yet — practise a few lessons first. Using longer everyday words for now."
                detailText = "Slow words (no data yet)"
            } else {
                infoLine = "Focusing on: " + built.words.joined(separator: "   ")
                detailText = "Slow words: " + built.words.joined(separator: " ")
            }

        case .stages:
            let stageTarget = s.stageSelected
            timeLimit = 0
            if s.warmupEnabled && s.warmupDay != Store.dayKey() {
                isWarmup = true
                let recent = store.data.history.filter { !$0.detail.hasPrefix("Warm-up") && !$0.detail.hasPrefix("Mistake replay") }.suffix(10)
                let avg = recent.isEmpty ? 40 : recent.map { $0.wpm }.reduce(0, +) / Double(recent.count)
                warmupPace = max(20, Int((avg * 0.7 / 5).rounded()) * 5)
                text = LessonBuilder.timedText(pool: 1000, count: 40)
                lessonLabel = "Warm-up — accuracy first"
                infoLine = "Relaxed warm-up for today: follow the pace caret at \(warmupPace) WPM (about 70% of your average) and aim for zero mistakes. It does not count towards your stage. Your stage lessons come next."
                detailText = "Warm-up (stage)"
            } else {
                let mix = s.stageMix(for: stageTarget)
                text = LessonBuilder.decorate(LessonBuilder.timedText(pool: 1000, count: max(10, s.stageMinWords)), capitals: mix.caps, punctuation: mix.punct)
                lessonLabel = "Stage \(stageTarget) WPM — lesson"
                infoLine = store.stageDayReport(target: stageTarget).text
                detailText = "Stage \(stageTarget) WPM lesson"
            }

        case .symbols:
            text = LessonBuilder.symbolsText(pool: s.wordPool, count: s.wordCount)
            lessonLabel = "Numbers & symbols"
            infoLine = "Digits, currency, brackets and punctuation mixed with everyday words."
            detailText = "Numbers & symbols"
        }

        if let rw = replay, !rw.isEmpty {
            isReplay = true
            isWarmup = false
            pendingBoostFlags = nil
            timeLimit = 0
            text = rw.flatMap { Array(repeating: $0, count: 5) }.joined(separator: " ")
            lessonLabel = "Mistake replay"
            infoLine = "Retype each word you slipped on 5 times in a row."
            detailText = "Mistake replay"
        }

        if mode != .passages && mode != .symbols && mode != .stages && !isReplay {
            text = LessonBuilder.decorate(text, capitals: s.capitalPercent, punctuation: s.punctuationPercent)
            if s.capitalPercent > 0 { detailText += " · caps \(s.capitalPercent)%" }
            if s.punctuationPercent > 0 { detailText += " · punct \(s.punctuationPercent)%" }
        }

        if s.mode == .smart {
            detailText = "Coach · " + detailText
            coachLine = "Smart coach — step \(smartStep + 1) of \(smartPlan.count): your weakest areas first, then a timed test. Press Return after each round."
        }

        if text.isEmpty { text = "Nothing to practise yet." }
        setTarget(text)
    }

    /// Called by the view with how many characters fit across the typing area, so lines fill the width.
    func setLineChars(_ n: Int) {
        let v = max(24, min(220, n))
        guard v != lineChars else { return }
        lineChars = v
        lines = PracticeController.wrapLines(target, maxLen: max(20, v - 1))
    }

    private func setTarget(_ text: String) {
        let chars = Array(text)
        target = chars
        states = Array(repeating: CharState.untyped, count: chars.count)
        var mask = Array(repeating: false, count: chars.count)
        if let flags = pendingBoostFlags {
            var t = 0
            for (k, ch) in chars.enumerated() {
                if ch == " " { t += 1; continue }
                if t < flags.count { mask[k] = flags[t] }
            }
        }
        boostMask = mask
        pendingBoostFlags = nil
        lines = PracticeController.wrapLines(chars, maxLen: max(20, lineChars - 1))

        var ranges: [Range<Int>] = []
        var idxAt = Array(repeating: -1, count: chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == " " {
                i += 1
                continue
            }
            let start = i
            while i < chars.count && chars[i] != " " { i += 1 }
            ranges.append(start..<i)
            for j in start..<i { idxAt[j] = ranges.count - 1 }
        }
        wordRanges = ranges
        wordIndexAt = idxAt
    }

    static func wrapLines(_ chars: [Character], maxLen: Int = 56) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = 0
        var lastSpace = -1
        var i = 0
        while i < chars.count {
            if chars[i] == " " { lastSpace = i }
            if i - start >= maxLen {
                if lastSpace >= start {
                    out.append(start..<(lastSpace + 1))
                    start = lastSpace + 1
                    lastSpace = -1
                } else {
                    out.append(start..<i)
                    start = i
                }
            }
            i += 1
        }
        if start < chars.count { out.append(start..<chars.count) }
        return out
    }

    // MARK: Navigation

    func retry() { newSession() }

    func proceed() {
        guard let r = result else { return }
        if r.passed == true, let key = currentKey {
            store.data.settings.lessonByKey[key] = lessonIndex + 1
        }
        newSession()
    }

    /// After a lesson: retype only the words you made mistakes on, once each.
    func startReplay() {
        guard let r = result, !missedWords.isEmpty else { return }
        if r.passed == true, let key = currentKey {
            store.data.settings.lessonByKey[key] = lessonIndex + 1
        }
        replayWords = missedWords
        newSession()
    }

    func dismissBreak() {
        breakDue = false
        activeSeconds = 0
    }

    /// Coach pacing: raise the pace caret when you beat it cleanly, lower it when it was too fast.
    private func adjustPace(wpm: Double, acc: Double) -> String? {
        let s = store.data.settings
        guard s.autoPace, currentMode != .stages else { return nil }
        var p = s.paceWPM
        if p == 0 {
            guard s.mode == .smart else { return nil }
            let recent = store.data.history.suffix(10)
            guard !recent.isEmpty else { return nil }
            let avg = recent.map { $0.wpm }.reduce(0, +) / Double(recent.count)
            p = max(10, Int((avg * 1.05 / 5).rounded()) * 5)
            store.data.settings.paceWPM = p
            return "The coach set your pace caret to \(p) WPM."
        }
        if acc >= 96 && wpm >= Double(p) {
            store.data.settings.paceWPM = min(250, p + 2)
            return "Clean and fast: the coach raised your pace caret to \(p + 2) WPM."
        }
        if acc < 93 || wpm < Double(p) * 0.85 {
            let np = max(10, p - 3)
            store.data.settings.paceWPM = np
            return "The coach eased your pace caret to \(np) WPM so you can stay accurate."
        }
        return nil
    }

    func stepLesson(_ delta: Int) {
        guard let key = currentKey, lessonCount > 0 else { return }
        var idx = lessonIndex + delta
        idx = ((idx % lessonCount) + lessonCount) % lessonCount
        store.data.settings.lessonByKey[key] = idx
        newSession()
    }

    // MARK: Keyboard

    func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.active, !self.showOptions, !self.breakDue, self.unlockMessage == nil else { return event }
            // Let text fields (e.g. the custom word box) receive their own typing.
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSText { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) { return event }
            switch event.keyCode {
            case 51: self.handle(.backspace); return nil
            case 36, 76: self.handle(.enter); return nil
            case 53: self.handle(.escape); return nil
            case 48: self.handle(.tab); return nil
            default: break
            }
            if let chars = event.characters, chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 32, scalar.value < 0xF700, scalar.value != 127 {
                self.handle(.char(Character(scalar)))
                return nil
            }
            return event
        }
    }

    /// Judges the stage after a stage lesson: your latest lessons at this stage decide.
    private func stageNote(reasons: String) -> String {
        let t = store.data.settings.stageSelected
        let rep = store.stageDayReport(target: t)
        if t <= store.data.settings.stageCleared {
            return reasons + " This stage was already cleared, so your ladder progress is unchanged."
        }
        if rep.cleared {
            store.data.settings.stageCleared = t
            if let nx = StageRules.next(after: t) {
                store.data.settings.stageSelected = nx
                unlockMessage = "You cleared the \(t) WPM stage and unlocked the \(nx) WPM stage. Great work!"
                return "Stage \(t) cleared! Stage \(nx) is now unlocked. " + rep.text
            }
            unlockMessage = "You cleared the \(t) WPM stage, the last one. You have completed every stage!"
            return "Stage \(t) cleared. You have completed every stage! " + rep.text
        }
        let more = max(0, rep.minLessons - rep.window)
        var tail = ""
        if more > 0 { tail = " At least \(more) more lesson(s) needed." }
        else { tail = " Keep going: you need \(rep.needPassed) passes among your latest \(rep.minLessons) lessons." }
        return reasons + " Not unlocked yet." + tail + " " + rep.text
    }

    func handle(_ e: KeyEvent) {
        if result != nil {
            switch e {
            case .enter: proceed()
            case .tab: if result?.passed == true { proceed() } else { retry() }
            case .escape: retry()
            default: break
            }
            return
        }
        switch e {
        case .escape, .tab: newSession()
        case .enter: break
        case .backspace: backspace()
        case .char(let ch): typeChar(ch)
        }
    }

    private func backspace() {
        if store.data.settings.strictMode { return }
        guard pos > 0 else { return }
        pos -= 1
        if states[pos] == .correct { correctCount -= 1 }
        states[pos] = .untyped
        prevExpected = pos > 0 ? target[pos - 1] : nil
        resetWordTracking()
    }

    // MARK: Word tracking

    private func resetWordTracking() {
        curWord = -1
        curSum = 0
        curCount = 0
        curErr = false
    }

    /// Records the word that was just completed (time between its keystrokes, and whether it had a mistake).
    private func finalizeWord() {
        defer { resetWordTracking() }
        guard curWord >= 0, curWord < wordRanges.count else { return }
        let r = wordRanges[curWord]
        let letters = String(target[r]).lowercased().filter { $0.isLetter }
        guard letters.count >= 3, curCount >= 2 else { return }
        var st = wordSession[letters] ?? KeyStat()
        st.attempts += 1
        if curErr { st.misses += 1 }
        st.totalMs += curSum
        st.timedCount += curCount
        wordSession[letters] = st
    }

    private func typeChar(_ ch: Character) {
        guard pos < target.count else { return }
        let strict = store.data.settings.strictMode
        let now = Date()
        if !started {
            started = true
            startDate = now
            startTimer()
        }
        let expected = target[pos]
        totalKeys += 1
        let isBoost = pos < boostMask.count && boostMask[pos]
        if isBoost { boostKeys += 1 }
        let ms: Double? = lastKeyTime.map { now.timeIntervalSince($0) * 1000 }
        lastKeyTime = now
        let correct = (ch == expected)

        let k = String(expected).lowercased()
        var st = keyStatsSession[k] ?? KeyStat()
        st.attempts += 1
        if let m = ms, m < 3000 {
            st.totalMs += m
            st.timedCount += 1
            intervals.append(m)
        }
        if !correct { st.misses += 1 }
        keyStatsSession[k] = st

        if let prev = prevExpected, prev.isLetter, expected.isLetter {
            let pk = String(prev).lowercased() + k
            var ps = pairSession[pk] ?? KeyStat()
            ps.attempts += 1
            if let m = ms, m < 3000 {
                ps.totalMs += m
                ps.timedCount += 1
            }
            if !correct { ps.misses += 1 }
            pairSession[pk] = ps
        }

        // Whole-word timing
        let widx = pos < wordIndexAt.count ? wordIndexAt[pos] : -1
        if widx >= 0 {
            if widx != curWord {
                finalizeWord()
                curWord = widx
            }
            if pos > wordRanges[widx].lowerBound, let m = ms, m < 3000 {
                curSum += m
                curCount += 1
            }
            if !correct { curErr = true }
        } else {
            finalizeWord()
        }

        if correct {
            correctKeys += 1
            if isBoost { boostCorrect += 1 }
            correctCount += 1
            states[pos] = .correct
        } else {
            states[pos] = .wrong
            play("Pop")
        }

        // In strict mode a wrong key does not move the cursor: the right key must be pressed.
        if correct || !strict {
            prevExpected = expected
            pos += 1
            if pos >= target.count { finish(timedOut: false) }
        }
    }

    // MARK: Timer and results

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard started, result == nil, let st = startDate else { return }
        elapsed = Date().timeIntervalSince(st)
        if timeLimit > 0 && elapsed >= timeLimit {
            finish(timedOut: true)
        }
    }

    private func play(_ name: String) {
        if store.data.settings.sounds {
            NSSound(named: NSSound.Name(name))?.play()
        }
    }

    private func topPairs(limit: Int) -> [String: KeyStat] {
        let ranked = pairSession
            .filter { $0.value.attempts >= 2 }
            .sorted { LessonBuilder.pairScore($0.value, minAttempts: 2) > LessonBuilder.pairScore($1.value, minAttempts: 2) }
            .prefix(limit)
        var out: [String: KeyStat] = [:]
        for (k, v) in ranked { out[k] = v }
        return out
    }

    private func topWords(limit: Int) -> [String: KeyStat] {
        let ranked = wordSession
            .sorted { ($0.value.avgMs + $0.value.missRate * 400) > ($1.value.avgMs + $1.value.missRate * 400) }
            .prefix(limit)
        var out: [String: KeyStat] = [:]
        for (k, v) in ranked { out[k] = v }
        return out
    }

    private func finish(timedOut: Bool) {
        guard result == nil else { return }
        timer?.invalidate()
        timer = nil
        finalizeWord()
        let s = store.data.settings

        var secs = elapsed
        if let st = startDate { secs = Date().timeIntervalSince(st) }
        if timedOut && timeLimit > 0 { secs = timeLimit }
        elapsed = secs

        let minutes = max(secs, 1) / 60
        let wpm = Double(correctCount) / 5 / minutes
        let rawWPM = Double(totalKeys) / 5 / minutes
        let acc = totalKeys == 0 ? 100 : Double(correctKeys) / Double(totalKeys) * 100

        // Consistency: how even your keystroke rhythm was (100 = perfectly steady).
        let steady = intervals.filter { $0 < 1000 }
        var consistency = 0.0
        if steady.count >= 10 {
            let mean = steady.reduce(0, +) / Double(steady.count)
            let variance = steady.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(steady.count)
            let cv = variance.squareRoot() / max(mean, 1)
            consistency = max(0, min(100, 100 * (1 - cv / 1.5)))
        }

        var passed: Bool? = nil
        var boostPassNote: String? = nil
        if (currentMode == .drills || currentMode == .passages) && !isReplay {
            var passAcc = acc
            if boostKeys > 0 && totalKeys > boostKeys {
                passAcc = Double(correctKeys - boostCorrect) / Double(totalKeys - boostKeys) * 100
            }
            passed = wpm >= Double(s.minWPM) && passAcc >= Double(s.minAccuracy)
            if boostKeys > 0 {
                boostPassNote = String(format: "Pass mark judged on the lesson words (accuracy %.1f%%); the mixed-in weak-spot words do not count against you.", passAcc)
            }
        }
        var note: String? = nil
        var isStage = false
        var stageReasons = ""
        if currentMode == .stages && isWarmup {
            store.data.settings.warmupDay = Store.dayKey()
            note = "Warm-up done. Press Return to start your stage lessons."
        } else if currentMode == .stages && !isReplay {
            isStage = true
            let t = s.stageSelected
            let need = s.stageAccuracy(for: t)
            let ok = wpm >= Double(t) && acc >= need
            passed = ok
            detailText += ok ? " · passed" : " · missed"
            var reasons: [String] = []
            if wpm < Double(t) { reasons.append("your speed (\(Int(wpm.rounded())) WPM) is below \(t)") }
            if acc < need { reasons.append(String(format: "your accuracy (%.1f%%) is below %.0f%%", acc, need)) }
            stageReasons = ok ? "This run counted as a pass." : "This run missed because " + reasons.joined(separator: " and ") + "."
        }
        if isReplay {
            missedWords = []
        } else {
            let slipped: [(String, Int)] = wordSession.compactMap { $0.value.misses > 0 ? ($0.key, $0.value.misses) : nil }
            let ordered = slipped.sorted { a, b in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
            missedWords = ordered.prefix(12).map { $0.0 }
        }

        result = SessionResult(
            wpm: wpm, rawWPM: rawWPM, accuracy: acc, consistency: consistency,
            seconds: secs, characters: correctCount, passed: passed, timedOut: timedOut,
            stage: isStage, note: note
        )

        if let p = passed {
            play(p ? "Glass" : "Basso")
        } else {
            play("Glass")
        }

        if totalKeys > 0 {
            let record = SessionRecord(
                mode: currentMode.rawValue,
                detail: detailText,
                wpm: wpm,
                accuracy: acc,
                seconds: secs,
                characters: correctCount,
                keys: keyStatsSession,
                rawWPM: rawWPM,
                consistency: steady.count >= 10 ? consistency : nil,
                pairs: topPairs(limit: 20),
                words: topWords(limit: 25)
            )
            store.data.history.append(record)
        }

        if isStage {
            result?.note = stageNote(reasons: stageReasons)
        }
        if let bn = boostPassNote {
            result?.note = [result?.note, bn].compactMap { $0 }.joined(separator: " ")
        }

        if !isReplay && !isWarmup {
            if let pn = adjustPace(wpm: wpm, acc: acc) {
                result?.note = [result?.note, pn].compactMap { $0 }.joined(separator: " ")
            }
            // The coach moves on to the next step unless a lesson was failed (then it repeats it).
            if s.mode == .smart && passed != false {
                smartStep += 1
            }
            lessonWPMs.append(wpm)
            avgWPM = lessonWPMs.reduce(0, +) / Double(lessonWPMs.count)
        }

        if store.data.settings.breakReminder {
            activeSeconds += secs
            if activeSeconds >= Double(max(10, store.data.settings.breakMinutes)) * 60 {
                breakDue = true
            }
        }
    }
}
