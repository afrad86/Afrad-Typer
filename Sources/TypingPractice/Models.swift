import Foundation

enum PracticeMode: String, CaseIterable, Identifiable, Codable {
    case smart = "Smart coach"
    case drills = "Lessons"
    case timed = "Timed"
    case passages = "Passages"
    case weakKeys = "Weak keys"
    case pairs = "Slow pairs"
    case slowWords = "Slow words"
    case symbols = "Numbers & symbols"
    case stages = "Stages"
    var id: String { rawValue }

    /// Short name for the mode picker.
    var label: String {
        switch self {
        case .smart: return "Coach"
        case .symbols: return "Symbols"
        default: return rawValue
        }
    }
}

enum DrillSource: String, CaseIterable, Identifiable, Codable {
    case trigrams = "Trigrams"
    case tetragrams = "Tetragrams"
    case words = "Words"
    case commonWords = "Common words"
    case custom = "Custom"
    var id: String { rawValue }
}

enum GeneratorStyle: String, CaseIterable, Identifiable, Codable {
    case combination = "Combination"
    case repetition = "Repetition"
    var id: String { rawValue }
}

struct KeyStat: Codable, Equatable {
    var attempts: Int = 0
    var misses: Int = 0
    var totalMs: Double = 0
    var timedCount: Int = 0
    var missRate: Double { attempts == 0 ? 0 : Double(misses) / Double(attempts) }
    var avgMs: Double { timedCount == 0 ? 0 : totalMs / Double(timedCount) }
}

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var mode: String
    var detail: String
    var wpm: Double
    var accuracy: Double
    var seconds: Double
    var characters: Int
    var keys: [String: KeyStat] = [:]
    var rawWPM: Double? = nil
    var consistency: Double? = nil
    var pairs: [String: KeyStat]? = nil
    var words: [String: KeyStat]? = nil
    var warm: Bool? = nil
    var replay: Bool? = nil

    /// Not a warm-up or a mistake replay. Older records (before the flags existed) are recognised by their label.
    var isCounted: Bool {
        if warm == true || replay == true { return false }
        return !detail.hasPrefix("Warm-up") && !detail.hasPrefix("Mistake replay")
    }
}

struct Passage: Codable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
    var text: String
}

struct AppSettings: Codable, Equatable {
    var mode: PracticeMode = .drills
    var source: DrillSource = .words
    var scope: Int = 50
    var generator: GeneratorStyle = .combination
    var minWPM: Int = 30
    var minAccuracy: Int = 95
    var itemsPerLesson: Int = 10
    var repetition: Int = 5
    var autoFocus: Bool = true
    var hideAhead: Int = 0
    var autoFocusPercent: Int = 40
    var mixedOrder: Bool = true
    var timedSeconds: Int = 60
    var sounds: Bool = true
    var capitalPercent: Int = 0
    var punctuationPercent: Int = 0
    var customWords: String = "the quick brown fox jumps over the lazy dog"
    var selectedPassage: UUID? = nil
    var lessonByKey: [String: Int] = [:]
    var targetWPM: Int = 110
    var paceWPM: Int = 0
    var strictMode: Bool = false
    var wordPool: Int = 1000
    var dailyGoalMinutes: Int = 20
    var wordCount: Int = 30
    var linesShown: Int = 4
    var stageCleared: Int = 40
    var stageSelected: Int = 45
    var stageClearedDay: String = ""
    var textSize: Int = 28
    var font: String = "mono"
    var stageAccuracyLow: Int = 97
    var stageAccuracyHigh: Int = 96
    var stageAutoMix: Bool = true
    var stageCapitals: Int = 5
    var stagePunctuation: Int = 5
    var warmupEnabled: Bool = true
    var warmupDay: String = ""
    var breakReminder: Bool = true
    var breakMinutes: Int = 25
    var autoPace: Bool = true
    /// Seconds without a key before the clock stops (0 = never).
    var afkSeconds: Int = 3
    var stageMinLessons: Int = 30
    var stageMinWords: Int = 200
    var stageLadderVersion: Int = 3
    var focusMode: Bool = false
    /// Remembered level (index) so the tag has a small buffer and does not flicker.
    var levelTier: Int? = nil
    var levelTierPlain: Int? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(PracticeMode.self, forKey: .mode)) ?? .drills
        source = (try? c.decode(DrillSource.self, forKey: .source)) ?? .words
        scope = try c.decodeIfPresent(Int.self, forKey: .scope) ?? 50
        generator = (try? c.decode(GeneratorStyle.self, forKey: .generator)) ?? .combination
        minWPM = try c.decodeIfPresent(Int.self, forKey: .minWPM) ?? 30
        minAccuracy = try c.decodeIfPresent(Int.self, forKey: .minAccuracy) ?? 95
        itemsPerLesson = try c.decodeIfPresent(Int.self, forKey: .itemsPerLesson) ?? 10
        repetition = try c.decodeIfPresent(Int.self, forKey: .repetition) ?? 5
        hideAhead = try c.decodeIfPresent(Int.self, forKey: .hideAhead) ?? 0
        autoFocus = try c.decodeIfPresent(Bool.self, forKey: .autoFocus) ?? true
        autoFocusPercent = try c.decodeIfPresent(Int.self, forKey: .autoFocusPercent) ?? 40
        mixedOrder = try c.decodeIfPresent(Bool.self, forKey: .mixedOrder) ?? true
        timedSeconds = try c.decodeIfPresent(Int.self, forKey: .timedSeconds) ?? 60
        if ![15, 30, 60, 120, 180].contains(timedSeconds) { timedSeconds = 60 }
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? true
        capitalPercent = try c.decodeIfPresent(Int.self, forKey: .capitalPercent) ?? 0
        punctuationPercent = try c.decodeIfPresent(Int.self, forKey: .punctuationPercent) ?? 0
        customWords = try c.decodeIfPresent(String.self, forKey: .customWords) ?? "the quick brown fox jumps over the lazy dog"
        selectedPassage = try c.decodeIfPresent(UUID.self, forKey: .selectedPassage)
        lessonByKey = try c.decodeIfPresent([String: Int].self, forKey: .lessonByKey) ?? [:]
        targetWPM = try c.decodeIfPresent(Int.self, forKey: .targetWPM) ?? 110
        paceWPM = try c.decodeIfPresent(Int.self, forKey: .paceWPM) ?? 0
        strictMode = try c.decodeIfPresent(Bool.self, forKey: .strictMode) ?? false
        wordPool = try c.decodeIfPresent(Int.self, forKey: .wordPool) ?? 1000
        if ![200, 500, 1000, 2000, 3000].contains(wordPool) { wordPool = wordPool > 2000 ? 3000 : (wordPool <= 300 ? 200 : 1000) }
        dailyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? 20
        wordCount = try c.decodeIfPresent(Int.self, forKey: .wordCount) ?? 30
        linesShown = try c.decodeIfPresent(Int.self, forKey: .linesShown) ?? 4
        stageClearedDay = try c.decodeIfPresent(String.self, forKey: .stageClearedDay) ?? ""
        focusMode = try c.decodeIfPresent(Bool.self, forKey: .focusMode) ?? false
        textSize = try c.decodeIfPresent(Int.self, forKey: .textSize) ?? 28
        font = try c.decodeIfPresent(String.self, forKey: .font) ?? "mono"
        stageAccuracyLow = try c.decodeIfPresent(Int.self, forKey: .stageAccuracyLow) ?? 97
        stageAccuracyHigh = try c.decodeIfPresent(Int.self, forKey: .stageAccuracyHigh) ?? 96
        stageAutoMix = try c.decodeIfPresent(Bool.self, forKey: .stageAutoMix) ?? true
        stageCapitals = try c.decodeIfPresent(Int.self, forKey: .stageCapitals) ?? 5
        stagePunctuation = try c.decodeIfPresent(Int.self, forKey: .stagePunctuation) ?? 5
        warmupEnabled = try c.decodeIfPresent(Bool.self, forKey: .warmupEnabled) ?? true
        warmupDay = try c.decodeIfPresent(String.self, forKey: .warmupDay) ?? ""
        breakReminder = try c.decodeIfPresent(Bool.self, forKey: .breakReminder) ?? true
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 25
        autoPace = try c.decodeIfPresent(Bool.self, forKey: .autoPace) ?? true
        afkSeconds = try c.decodeIfPresent(Int.self, forKey: .afkSeconds) ?? 3
        stageMinLessons = try c.decodeIfPresent(Int.self, forKey: .stageMinLessons) ?? 30
        levelTier = try c.decodeIfPresent(Int.self, forKey: .levelTier)
        levelTierPlain = try c.decodeIfPresent(Int.self, forKey: .levelTierPlain)
        stageMinWords = try c.decodeIfPresent(Int.self, forKey: .stageMinWords) ?? 200
        let ver = try c.decodeIfPresent(Int.self, forKey: .stageLadderVersion) ?? 1
        if ver < 2 {
            // The ladder changed (now 45 to 110 WPM), so progress starts again from the bottom.
            stageCleared = 40
            stageSelected = 45
            stageClearedDay = ""
        } else {
            stageCleared = try c.decodeIfPresent(Int.self, forKey: .stageCleared) ?? 40
            stageSelected = try c.decodeIfPresent(Int.self, forKey: .stageSelected) ?? 45
        }
        if ver < 3 {
            // The ladder now has steps of 5 up to 80 and steps of 3 after that.
            stageCleared = ([40] + StageRules.targets).last { $0 <= stageCleared } ?? 40
            stageSelected = StageRules.next(after: stageCleared) ?? (StageRules.targets.last ?? 110)
        }
        stageLadderVersion = 3
    }

    /// Capital-letter and punctuation share used in stage lessons. Automatic mode starts plain and ramps
    /// up towards real-text levels, so the early stages stay comfortable.
    func stageMix(for target: Int) -> (caps: Int, punct: Int) {
        if !stageAutoMix { return (stageCapitals, stagePunctuation) }
        switch target {
        case ..<60: return (0, 0)
        case 60..<80: return (3, 3)
        case 80..<95: return (5, 5)
        default: return (8, 8)
        }
    }

    /// Accuracy needed for a stage: stricter at lower speeds.
    func stageAccuracy(for target: Int) -> Double {
        Double(target <= 85 ? stageAccuracyLow : stageAccuracyHigh)
    }

    /// Changes to any of these fields restart the current exercise.
    var configKey: String {
        "\(mode.rawValue)|\(source.rawValue)|\(scope)|\(generator.rawValue)|\(itemsPerLesson)|\(repetition)|\(mixedOrder)|\(autoFocus)|\(timedSeconds)|\(capitalPercent)|\(punctuationPercent)|\(wordPool)|\(wordCount)|\(customWords)|\(selectedPassage?.uuidString ?? "")"
    }
}

struct StoreData: Codable {
    var settings = AppSettings()
    var history: [SessionRecord] = []
    var passages: [Passage] = []
    var historyResetAt: Date? = nil
    var deletedPassages: [UUID] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        history = try c.decodeIfPresent([SessionRecord].self, forKey: .history) ?? []
        passages = try c.decodeIfPresent([Passage].self, forKey: .passages) ?? []
        historyResetAt = try c.decodeIfPresent(Date.self, forKey: .historyResetAt)
        deletedPassages = try c.decodeIfPresent([UUID].self, forKey: .deletedPassages) ?? []
    }
}

/// The strict stage ladder: steps of 5 WPM up to 80, then steps of 3 up to 110.
/// Each stage lesson is 200 words (adjustable). To unlock the next stage you must finish at least
/// 30 lessons at the stage, and in your latest 30 lessons at least 90% must reach the stage speed with
/// the required accuracy (97% up to 85 WPM, 96% from 86 WPM by default). It can take as many days as you need.
enum StageRules {
    static let targets: [Int] = [45, 50, 55, 60, 65, 70, 75, 80, 83, 86, 89, 92, 95, 98, 101, 104, 107, 110]
    static let passFraction: Double = 0.9

    static func next(after c: Int) -> Int? { targets.first { $0 > c } }
    static func previous(of t: Int) -> Int { targets.last { $0 < t } ?? 40 }
}

struct StageDayReport {
    var attempts: Int      // stage lessons finished at this stage, ever
    var window: Int        // latest lessons considered (up to the minimum lesson count)
    var passed: Int        // of those, how many reached the speed and accuracy
    var minLessons: Int
    var wordsPerLesson: Int
    var target: Int
    var accuracy: Double

    var needPassed: Int { Int((Double(minLessons) * StageRules.passFraction).rounded(.up)) }
    var cleared: Bool { window >= minLessons && passed >= needPassed }

    var text: String {
        return "Stage \(target) WPM: \(attempts) lessons finished. In your latest \(minLessons), \(passed) passed (\(passed) of \(window); you need \(needPassed) of \(minLessons)). Each lesson is \(wordsPerLesson) words at \(target)+ WPM with \(Int(accuracy))%+ accuracy."
    }
}

enum Starter {
    static let passages: [Passage] = [
        Passage(
            title: "Starter: Typing basics",
            url: "built-in",
            text: "Typing well is a skill that grows with steady practice. Keep your eyes on the screen, rest your fingers on the home row, and let accuracy come before speed. Speed is a side effect of smooth, relaxed movement. When you make a mistake, slow down for a moment and find your rhythm again. Short sessions work better than long ones. Ten focused minutes each day will teach your hands more than one tiring hour at the weekend. Notice which keys slow you down, then drill them until they feel as easy as the rest."
        ),
        Passage(
            title: "Starter: Genomic surveillance",
            url: "built-in",
            text: "Genomic surveillance helps public health teams detect new variants of a pathogen early. Sequencing data are combined with clinical and epidemiological records so that outbreaks can be traced and controlled quickly. Good surveillance depends on careful sampling, clear data reporting, and open sharing between laboratories. Over time, the same data can show how antimicrobial resistance spreads and which interventions work best."
        )
    ]
}
