import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    var onGo: (PracticeMode) -> Void

    private struct PlanItem: Identifiable {
        let key: String
        let mode: PracticeMode
        let title: String
        let detail: String
        let share: Double
        /// Minutes of this mode that belong to an earlier step (the warm-up and lessons share Lessons time).
        let offsetShare: Double
        var id: String { key }
    }

    private let plan: [PlanItem] = [
        PlanItem(key: "warmup", mode: .drills, title: "Warm-up", detail: "An easy lesson, slowly. Aim for 100% accuracy, not speed.", share: 0.15, offsetShare: 0),
        PlanItem(key: "lessons", mode: .drills, title: "Lessons", detail: "Your lessons, with your weak keys, pairs and words mixed in automatically.", share: 0.40, offsetShare: 0.15),
        PlanItem(key: "timed", mode: .timed, title: "Timed tests", detail: "Push your speed. The coach adjusts the pace caret for you.", share: 0.25, offsetShare: 0),
        PlanItem(key: "passages", mode: .passages, title: "Real text", detail: "Relax into a steady rhythm on a whole passage.", share: 0.20, offsetShare: 0)
    ]

    private func minutes(_ share: Double) -> Int {
        max(1, Int((Double(store.data.settings.dailyGoalMinutes) * share).rounded()))
    }

    var body: some View {
        let goal = max(1, store.data.settings.dailyGoalMinutes)
        let todayMin = store.secondsToday() / 60
        let target = max(1, store.data.settings.targetWPM)
        let recent = store.data.history.suffix(10)
        let avg10 = recent.isEmpty ? 0 : recent.map { $0.wpm }.reduce(0, +) / Double(recent.count)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Daily Practice").font(.largeTitle.bold())
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Button("Start coached session") { onGo(.smart) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Text("One click: the coach drills your weakest keys, letter pairs and words, then finishes with a timed test. Or follow the plan below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    VStack(spacing: 8) {
                        StatTile(
                            title: "Minutes today (goal \(goal))",
                            value: String(format: "%.0f", todayMin),
                            color: todayMin >= Double(goal) ? Color(nsColor: .systemGreen) : Color.primary
                        )
                        ProgressView(value: min(todayMin / Double(goal), 1.0))
                    }
                    StatTile(title: "Day streak", value: "\(store.streak)")
                    VStack(spacing: 8) {
                        StatTile(title: "Average of last 10 (goal \(target))", value: String(format: "%.0f WPM", avg10))
                        ProgressView(value: min(avg10 / Double(target), 1.0))
                    }
                }

                HStack {
                    Stepper("Daily goal: \(goal) minutes", value: $store.data.settings.dailyGoalMinutes, in: 5...180, step: 5)
                        .frame(width: 280)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested session").font(.title2.bold())
                    Text("Short, focused practice beats long occasional sessions. Stay above 95% accuracy and your speed will follow.")
                        .foregroundStyle(.secondary)
                    ForEach(plan) { item in
                        let need = minutes(item.share)
                        let offset = item.offsetShare > 0 ? Double(minutes(item.offsetShare)) : 0
                        let done = max(0, store.secondsToday(mode: item.mode) / 60 - offset)
                        let finished = done >= Double(need)
                        HStack(spacing: 12) {
                            Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(finished ? Color(nsColor: .systemGreen) : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.title) — \(String(format: "%.0f", min(done, Double(need)))) / \(need) min")
                                    .font(.body.weight(.medium))
                                Text(item.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(finished ? "Again" : "Start") { onGo(item.mode) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
                    }
                }
            }
            .padding(24)
        }
    }
}
