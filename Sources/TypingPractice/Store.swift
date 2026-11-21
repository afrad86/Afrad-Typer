import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class Store: ObservableObject {
    @Published var data: StoreData {
        didSet { if !merging { save() } }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    let fileURL: URL
    let syncing: Bool
    private var merging = false
    private var pendingSave: DispatchWorkItem? = nil
    private static let writer = DispatchQueue(label: "afrad.store.writer", qos: .utility)

    /// Only the latest sessions keep their per-key, pair and word details (the analysis uses the last 20);
    /// older ones keep the summary, so the file stays small and saving stays quick.
    static let detailKeep = 50

    // Cached results for the sidebar, recalculated only when the history changes.
    private var levelKey = ""
    private var levelValue: LevelCalc.Result? = nil
    private var countValue = 0
    private var todayKey = ""
    private var todayValue = 0.0

    init(fileURL: URL, syncing: Bool = false) {
        self.fileURL = fileURL
        self.syncing = syncing
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? Store.decoder.decode(StoreData.self, from: raw) {
            data = decoded
        } else {
            data = StoreData()
        }
        if data.passages.isEmpty {
            data.passages = Starter.passages
        }
        if syncing {
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.mergeFromDisk()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.flush()
        }
    }

    /// Changes are written at most about once a second, in the background, instead of at every click.
    private func save() {
        pendingSave?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    /// Writes any waiting change straight away (used when switching user and when the app quits).
    func flush() {
        guard let w = pendingSave else { return }
        w.cancel()
        pendingSave = nil
        saveNow(wait: true)
    }

    private func saveNow(wait: Bool = false) {
        pendingSave = nil
        if syncing { mergeQuietly() }
        writeNow(wait: wait)
    }

    private static func compacted(_ d: StoreData) -> StoreData {
        var c = d
        let cut = c.history.count - Store.detailKeep
        if cut > 0 {
            for i in 0..<cut where !c.history[i].keys.isEmpty || c.history[i].pairs != nil || c.history[i].words != nil {
                c.history[i].keys = [:]
                c.history[i].pairs = nil
                c.history[i].words = nil
            }
        }
        return c
    }

    private func writeNow(wait: Bool = false) {
        let snapshot = Store.compacted(data)
        let url = fileURL
        let job = {
            do {
                let raw = try Store.encoder.encode(snapshot)
                try raw.write(to: url, options: .atomic)
            } catch {
                print("Save failed: \(error)")
            }
        }
        if wait { Store.writer.sync(execute: job) } else { Store.writer.async(execute: job) }
    }

    // MARK: Cached sidebar values

    private var historyStamp: String { "\(data.history.count)|\(data.history.last?.id.uuidString ?? "")" }

    /// Your level, worked out again only when a session is added or the stored tier changes.
    var level: LevelCalc.Result? {
        let k = historyStamp + "|\(data.settings.levelTier ?? -1)|\(data.settings.levelTierPlain ?? -1)"
        if k != levelKey {
            levelKey = k
            levelValue = LevelCalc.assess(data.history, storedTier: data.settings.levelTier, storedPlain: data.settings.levelTierPlain)
            countValue = LevelCalc.sessions(data.history).count
        }
        return levelValue
    }

    var levelSessionCount: Int {
        _ = level
        return countValue
    }

    /// Minutes typed today, cached until the history or the day changes.
    var minutesToday: Double {
        let k = historyStamp + "|" + Store.dayKey()
        if k != todayKey {
            todayKey = k
            todayValue = secondsToday() / 60
        }
        return todayValue
    }

    /// Pulls in anything the other Mac added (iCloud Drive sync) without writing.
    @discardableResult
    private func mergeQuietly() -> Bool {
        guard let raw = try? Data(contentsOf: fileURL),
              let other = try? Store.decoder.decode(StoreData.self, from: raw) else { return false }
        let (d, changed) = Store.merge(data, other)
        if changed {
            merging = true
            data = d
            merging = false
        }
        return changed
    }

    func mergeFromDisk() {
        if mergeQuietly() { writeNow() }
    }

    /// Combines two copies of one user's data. History and passages are unioned; stage progress takes the furthest.
    static func merge(_ a: StoreData, _ b: StoreData) -> (StoreData, Bool) {
        var d = a
        var changed = false
        let cutoff = [a.historyResetAt, b.historyResetAt].compactMap { $0 }.max()
        if cutoff != a.historyResetAt { d.historyResetAt = cutoff; changed = true }

        var tomb = Set(a.deletedPassages)
        let before = tomb.count
        tomb.formUnion(b.deletedPassages)
        if tomb.count != before { d.deletedPassages = Array(tomb); changed = true }

        if let c = cutoff {
            let kept = d.history.filter { $0.date > c }
            if kept.count != d.history.count { d.history = kept; changed = true }
        }
        let ids = Set(d.history.map { $0.id })
        var add = b.history.filter { !ids.contains($0.id) }
        if let c = cutoff { add = add.filter { $0.date > c } }
        if !add.isEmpty {
            d.history.append(contentsOf: add)
            d.history.sort { $0.date < $1.date }
            changed = true
        }

        func key(_ p: Passage) -> String { p.url == "built-in" ? "b:" + p.title : p.id.uuidString }
        let keptP = d.passages.filter { !tomb.contains($0.id) }
        if keptP.count != d.passages.count { d.passages = keptP; changed = true }
        var have = Set(d.passages.map { key($0) })
        for p in b.passages where !tomb.contains(p.id) && !have.contains(key(p)) {
            d.passages.append(p)
            have.insert(key(p))
            changed = true
        }

        if b.settings.stageCleared > d.settings.stageCleared {
            d.settings.stageCleared = b.settings.stageCleared
            d.settings.stageSelected = max(d.settings.stageSelected, b.settings.stageSelected)
            changed = true
        }
        return (d, changed)
    }

    func resetHistory() {
        data.historyResetAt = Date()
        data.history = []
    }

    func deletePassage(_ id: UUID) {
        data.passages.removeAll { $0.id == id }
        if !data.deletedPassages.contains(id) { data.deletedPassages.append(id) }
        if data.settings.selectedPassage == id { data.settings.selectedPassage = nil }
    }

    /// Per-key statistics, summed over every saved session.
    /// The sessions used for assessment: all of them, or only the latest `n` (so fixed weaknesses fade out).
    func recentRecords(_ n: Int?) -> ArraySlice<SessionRecord> {
        // Warm-ups and mistake replays are left out, so repeated replay words do not skew the analysis.
        let counted = data.history.filter { $0.isCounted }
        guard let n = n else { return counted[...] }
        return counted.suffix(n)
    }

    var keyStats: [String: KeyStat] { keyStats(last: nil) }
    var pairStats: [String: KeyStat] { pairStats(last: nil) }
    var wordStats: [String: KeyStat] { wordStats(last: nil) }
    var baselineMs: Double { baselineMs(last: nil) }

    func keyStats(last n: Int?) -> [String: KeyStat] {
        var out: [String: KeyStat] = [:]
        for r in recentRecords(n) {
            for (k, v) in r.keys {
                var cur = out[k] ?? KeyStat()
                cur.attempts += v.attempts
                cur.misses += v.misses
                cur.totalMs += v.totalMs
                cur.timedCount += v.timedCount
                out[k] = cur
            }
        }
        return out
    }

    /// Per letter-pair statistics (each session stores its slowest/most-missed pairs).
    func pairStats(last n: Int?) -> [String: KeyStat] {
        var out: [String: KeyStat] = [:]
        for r in recentRecords(n) {
            for (k, v) in (r.pairs ?? [:]) {
                var cur = out[k] ?? KeyStat()
                cur.attempts += v.attempts
                cur.misses += v.misses
                cur.totalMs += v.totalMs
                cur.timedCount += v.timedCount
                out[k] = cur
            }
        }
        return out
    }

    /// Per whole-word statistics (each session stores its slowest/most-missed words).
    /// `avgMs` is the average time between keystrokes inside the word.
    func wordStats(last n: Int?) -> [String: KeyStat] {
        var out: [String: KeyStat] = [:]
        for r in recentRecords(n) {
            for (k, v) in (r.words ?? [:]) {
                var cur = out[k] ?? KeyStat()
                cur.attempts += v.attempts
                cur.misses += v.misses
                cur.totalMs += v.totalMs
                cur.timedCount += v.timedCount
                out[k] = cur
            }
        }
        return out
    }

    /// Your overall average time between keystrokes (ms); the yardstick for "slow" words.
    func baselineMs(last window: Int?) -> Double {
        var total = 0.0
        var n = 0
        for (_, v) in keyStats(last: window) {
            total += v.totalMs
            n += v.timedCount
        }
        return n > 0 ? total / Double(n) : 0
    }

    static func dayKey(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Only lessons done inside the Stages track count. Your latest N lessons at this stage are judged.
    func stageDayReport(target: Int) -> StageDayReport {
        let prefix = "Stage \(target) WPM"
        let acc = data.settings.stageAccuracy(for: target)
        let runs = data.history.filter { $0.mode == PracticeMode.stages.rawValue && $0.detail.hasPrefix(prefix) }
        let minL = max(1, data.settings.stageMinLessons)
        let outs = runs.map { $0.wpm >= Double(target) && $0.accuracy >= acc }
        let pool = StageDayReport.pool(outs, size: minL)
        return StageDayReport(attempts: runs.count, window: pool.count, passed: pool.filter { $0 }.count,
                              minLessons: minL, wordsPerLesson: max(10, data.settings.stageMinWords), target: target, accuracy: acc,
                              outcomes: outs)
    }

    func secondsToday(mode: PracticeMode? = nil) -> Double {
        let cal = Calendar.current
        var total = 0.0
        for r in data.history where cal.isDateInToday(r.date) {
            if let m = mode, r.mode != m.rawValue { continue }
            total += r.seconds
        }
        return total
    }

    /// Consecutive days with at least one session, counting back from today (or yesterday if you haven't practised yet today).
    var streak: Int {
        let cal = Calendar.current
        let days = Set(data.history.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    // MARK: Passages

    @MainActor
    func addPassage(urlString: String) async throws {
        var t = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { throw PassageError.badURL }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        guard let url = URL(string: t), url.host != nil else { throw PassageError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let (raw, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PassageError.http(http.statusCode)
        }
        let html = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? ""
        let result = WebExtractor.extract(html: html)
        guard result.text.count >= 80 else { throw PassageError.noText }
        let title = result.title.isEmpty ? (url.host ?? t) : result.title
        data.passages.append(Passage(title: title, url: t, text: result.text))
    }

    func addPastedPassage(title: String, text: String) -> Bool {
        let clean = WebExtractor.normalize(text)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 20 else { return false }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        data.passages.append(Passage(title: t.isEmpty ? "Pasted text" : t, url: "pasted", text: clean))
        return true
    }

    // MARK: Backup

    /// Local folder with the automatic weekly backups (kept on this Mac, never synced).
    static var backupsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypingPractice", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// Writes a backup of this user's data once a week, keeping the newest 8.
    func autoBackup(label: String) {
        let fm = FileManager.default
        let dir = Store.backupsFolder
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = String(label.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        let prefix = (safe.isEmpty ? "user" : safe) + "-"
        let existing = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let last = existing.last,
           let d = (try? last.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(d) < 7 * 86400 {
            return
        }
        guard !data.history.isEmpty else { return }
        let url = dir.appendingPathComponent(prefix + Store.dayKey() + ".json")
        guard let raw = try? Store.encoder.encode(data), (try? raw.write(to: url, options: .atomic)) != nil else { return }
        let all = existing.filter { $0 != url } + [url]
        if all.count > 8 {
            for f in all.prefix(all.count - 8) { try? fm.removeItem(at: f) }
        }
    }

    func showBackups() {
        try? FileManager.default.createDirectory(at: Store.backupsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Store.backupsFolder)
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "typing-practice-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try Store.encoder.encode(data).write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Merges a backup into the current data (history and passages are de-duplicated by id).
    func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let raw = try Data(contentsOf: url)
            let other = try Store.decoder.decode(StoreData.self, from: raw)
            var d = data
            let historyIDs = Set(d.history.map { $0.id })
            d.history.append(contentsOf: other.history.filter { !historyIDs.contains($0.id) })
            let passageIDs = Set(d.passages.map { $0.id })
            d.passages.append(contentsOf: other.passages.filter { !passageIDs.contains($0.id) })
            data = d
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
