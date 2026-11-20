import SwiftUI

struct ProgressScreen: View {
    @EnvironmentObject var store: Store
    @StateObject private var filterBox = Box("All")
    @StateObject private var resetBox = Box(false)

    private struct Point: Identifiable {
        let id: Int
        let wpm: Double
        let acc: Double
        let avg: Double
    }

    private var filtered: [SessionRecord] {
        let sorted = store.data.history.filter { !$0.detail.hasPrefix("Warm-up") && !$0.detail.hasPrefix("Mistake replay") }.sorted { $0.date < $1.date }
        return filterBox.value == "All" ? sorted : sorted.filter { $0.mode == filterBox.value }
    }

    private var points: [Point] {
        let list = filtered
        var out: [Point] = []
        for (i, r) in list.enumerated() {
            let lo = max(0, i - 9)
            let window = list[lo...i]
            let avg = window.map { $0.wpm }.reduce(0, +) / Double(window.count)
            out.append(Point(id: i + 1, wpm: r.wpm, acc: r.accuracy, avg: avg))
        }
        return out
    }

    private var last10: [SessionRecord] { Array(filtered.suffix(10)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Progress").font(.largeTitle.bold())
                    Spacer()
                    Picker("Show", selection: $filterBox.value) {
                        Text("All").tag("All")
                        ForEach(PracticeMode.allCases.filter { $0 != .smart }) { m in
                            Text(m.rawValue).tag(m.rawValue)
                        }
                    }
                    .frame(width: 280)
                }

                goalCard

                RoadAndCalendar()

                if filtered.isEmpty {
                    Text("No sessions yet. Finish a lesson, timed test or passage and it will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    summary
                    wpmChart
                    chartCard(title: "Accuracy (%) per session") {
                        LineChartView(
                            series: [ChartSeries(values: points.map { $0.acc }, color: Color.orange, lineWidth: 2, showPoints: true)],
                            yMin: 50,
                            yMax: 100
                        )
                    }
                    recent
                }

                HStack(spacing: 12) {
                    Button("Export backup…") { store.exportData() }
                    Button("Import backup…") { store.importData() }
                    Button("Show weekly backups") { store.showBackups() }
                        .help("The app saves a backup of your data automatically once a week (newest 8 kept)")
                    Spacer()
                    Button("Reset history…", role: .destructive) { resetBox.value = true }
                }
                Text("Your data is stored on this Mac (or in iCloud Drive if you turned on sync at the user screen). Export/Import also works for moving history by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .confirmationDialog("Delete all practice history on this Mac?", isPresented: $resetBox.value) {
            Button("Delete history", role: .destructive) { store.resetHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Goal

    private var goalCard: some View {
        let target = max(1, store.data.settings.targetWPM)
        let best = filtered.map { $0.wpm }.max() ?? 0
        let avg10 = last10.isEmpty ? 0 : last10.map { $0.wpm }.reduce(0, +) / Double(last10.count)
        let togo = max(0, target - Int(avg10.rounded()))
        let pct = Int((min(avg10 / Double(target), 1.0) * 100).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goal: \(target) WPM").font(.headline)
                Spacer()
                Stepper("Goal", value: $store.data.settings.targetWPM, in: 20...250, step: 5)
                    .labelsHidden()
            }
            ProgressView(value: min(avg10 / Double(target), 1.0))
            Text("Average of last 10 sessions: \(Int(avg10.rounded())) WPM (\(pct)% of goal)  ·  Best: \(Int(best.rounded())) WPM  ·  \(togo) WPM to go")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private var wpmChart: some View {
        let target = Double(store.data.settings.targetWPM)
        let best = filtered.map { $0.wpm }.max() ?? 0
        let yMax = max(target, best) + 10
        return chartCard(title: "Speed (WPM) per session") {
            LineChartView(
                series: [
                    ChartSeries(values: points.map { $0.wpm }, color: Color.blue.opacity(0.55), lineWidth: 1.5, showPoints: true),
                    ChartSeries(values: points.map { $0.avg }, color: Color.purple, lineWidth: 3)
                ],
                yMin: 0,
                yMax: yMax,
                goal: target
            )
        }
    }

    // MARK: Summary and lists

    private var summary: some View {
        let best = filtered.map { $0.wpm }.max() ?? 0
        let avgWPM = last10.isEmpty ? 0 : last10.map { $0.wpm }.reduce(0, +) / Double(last10.count)
        let avgAcc = last10.isEmpty ? 0 : last10.map { $0.accuracy }.reduce(0, +) / Double(last10.count)
        let cons = last10.compactMap { $0.consistency }
        let avgCons = cons.isEmpty ? 0 : cons.reduce(0, +) / Double(cons.count)
        let minutes = filtered.map { $0.seconds }.reduce(0, +) / 60
        return HStack(spacing: 12) {
            StatTile(title: "Sessions", value: "\(filtered.count)")
            StatTile(title: "Best WPM", value: String(format: "%.0f", best))
            StatTile(title: "Avg WPM (last 10)", value: String(format: "%.0f", avgWPM))
            StatTile(title: "Avg accuracy (last 10)", value: String(format: "%.1f%%", avgAcc))
            StatTile(title: "Consistency (last 10)", value: cons.isEmpty ? "–" : String(format: "%.0f%%", avgCons))
            StatTile(title: "Minutes practised", value: String(format: "%.0f", minutes))
        }
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().frame(height: 200)
            if title.hasPrefix("Speed") {
                Text("Blue dots: each session  ·  purple line: average of the last 10  ·  green dashed line: your goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent sessions").font(.headline)
            ForEach(Array(filtered.suffix(30).reversed())) { r in
                HStack {
                    Text(r.date, format: .dateTime.month().day().hour().minute())
                        .frame(width: 120, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(r.mode).frame(width: 130, alignment: .leading)
                    Text(r.detail).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.0f WPM", r.wpm)).frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.1f%%", r.accuracy)).frame(width: 70, alignment: .trailing)
                    Text(r.consistency.map { String(format: "%.0f%%", $0) } ?? "–")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Divider()
            }
        }
    }
}
