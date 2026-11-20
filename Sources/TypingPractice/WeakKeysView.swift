import SwiftUI

struct WeakKeysView: View {
    @EnvironmentObject var store: Store

    private let rows: [[Character]] = [
        Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")
    ]
    private let offsets: [CGFloat] = [0, 26, 62]

    private struct StatRow: Identifiable {
        let id: String
        let stat: KeyStat
    }

    private var weakRows: [StatRow] {
        let all: [StatRow] = store.keyStats(last: 20)
            .filter { $0.key.count == 1 && $0.key != " " && $0.value.attempts >= 5 }
            .map { StatRow(id: $0.key, stat: $0.value) }
        let sorted = all.sorted { LessonBuilder.weakScore($0.stat) > LessonBuilder.weakScore($1.stat) }
        return Array(sorted.prefix(12))
    }

    private var pairRows: [StatRow] {
        let all: [StatRow] = store.pairStats(last: 20)
            .filter { $0.value.attempts >= 3 }
            .map { StatRow(id: $0.key, stat: $0.value) }
        let sorted = all.sorted { LessonBuilder.pairScore($0.stat) > LessonBuilder.pairScore($1.stat) }
        return Array(sorted.prefix(12))
    }

    private var wordRows: [StatRow] {
        let base = store.baselineMs(last: 20)
        let all: [StatRow] = store.wordStats(last: 20)
            .filter { $0.value.attempts >= 2 }
            .map { StatRow(id: $0.key, stat: $0.value) }
        let sorted = all.sorted { LessonBuilder.wordScore($0.stat, baseline: base) > LessonBuilder.wordScore($1.stat, baseline: base) }
        return Array(sorted.prefix(12))
    }

    private func color(for ch: Character, stats: [String: KeyStat]) -> Color {
        guard let st = stats[String(ch)], st.attempts >= 5 else {
            return Color.gray.opacity(0.25)
        }
        let r = min(st.missRate / 0.15, 1.0)
        return Color(hue: 0.33 * (1 - r), saturation: 0.65, brightness: 0.85)
    }

    private func help(for ch: Character, stats: [String: KeyStat]) -> String {
        guard let st = stats[String(ch)], st.attempts > 0 else {
            return "\(ch): no data yet"
        }
        let missed = String(format: "%.0f", st.missRate * 100)
        let speed = String(format: "%.0f", st.avgMs)
        return "\(ch): \(missed)% missed, \(speed) ms average, \(st.attempts) presses"
    }

    var body: some View {
        let stats = store.keyStats(last: 20)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Weak Spots").font(.largeTitle.bold())
                Text("Based on your last 20 sessions, so it changes as you improve. This is a report only. Your Lessons already use it automatically: every lesson adds extra practice on your weakest keys, slow pairs and slow words.")
                    .foregroundStyle(.secondary)
                Text("Every key you press is tracked. Red keys are missed most often; grey keys don't have enough data yet (5+ presses needed). Hover a key for details.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<rows.count, id: \.self) { i in
                        HStack(spacing: 8) {
                            ForEach(rows[i], id: \.self) { ch in
                                Text(String(ch).uppercased())
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .frame(width: 52, height: 52)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(color(for: ch, stats: stats)))
                                    .help(help(for: ch, stats: stats))
                            }
                        }
                        .padding(.leading, offsets[i])
                    }
                }

                if weakRows.isEmpty {
                    Text(stats.isEmpty ? "No data yet — do a few lessons and come back." : "Nothing stands out yet — keep practising.")
                        .foregroundStyle(.secondary)
                } else {
                    table(title: "Your weakest keys", firstColumn: "Key", rows: weakRows)
                }


                Divider()

                Text("Slow letter pairs").font(.title2.bold())
                Text("At higher speeds the bottleneck is usually the move between two particular letters. These are the pairs where you are slowest or slip most.")
                    .foregroundStyle(.secondary)

                if pairRows.isEmpty {
                    Text("Not enough pair data yet — finish a few sessions and come back.")
                        .foregroundStyle(.secondary)
                } else {
                    table(title: "Your slowest pairs", firstColumn: "Pair", rows: pairRows)
                }


                Divider()

                Text("Slow words").font(.title2.bold())
                Text("Whole words you type slowest or get wrong most. Speed here is the average time between keystrokes inside the word.")
                    .foregroundStyle(.secondary)

                if wordRows.isEmpty {
                    Text("Not enough word data yet — finish a few sessions and come back.")
                        .foregroundStyle(.secondary)
                } else {
                    table(title: "Your slowest words", firstColumn: "Word", rows: wordRows)
                }

            }
            .padding(24)
        }
    }

    private func table(title: String, firstColumn: String, rows: [StatRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            HStack {
                Text(firstColumn).frame(width: 110, alignment: .leading)
                Text("Presses").frame(width: 90, alignment: .trailing)
                Text("Missed").frame(width: 90, alignment: .trailing)
                Text("Avg speed").frame(width: 110, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(rows) { r in
                HStack {
                    Text(r.id.uppercased()).bold().frame(width: 110, alignment: .leading)
                    Text("\(r.stat.attempts)").frame(width: 90, alignment: .trailing)
                    Text(String(format: "%.1f%%", r.stat.missRate * 100)).frame(width: 90, alignment: .trailing)
                    Text(String(format: "%.0f ms", r.stat.avgMs)).frame(width: 110, alignment: .trailing)
                }
            }
        }
    }
}
