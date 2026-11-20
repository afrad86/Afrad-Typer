import SwiftUI
import AppKit

enum AppTab: String, CaseIterable, Identifiable {
    case today = "Daily Practice"
    case practice = "Practice"
    case stages = "Advanced"
    case progress = "Progress"
    case weakKeys = "Weak Spots"
    case library = "Library"
    case guide = "How it works"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: return "target"
        case .practice: return "keyboard"
        case .stages: return "flag.checkered"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .weakKeys: return "exclamationmark.triangle"
        case .library: return "books.vertical"
        case .guide: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var c: PracticeController
    @EnvironmentObject var session: AppSession
    var userName: String = ""
    @StateObject private var tabBox = Box<AppTab?>(.practice)
    @StateObject private var guideFocus = Box<String>("level")

    private func showGuide(_ id: String) {
        guideFocus.value = id
        tabBox.value = .guide
    }

    private var hideSidebar: Bool {
        c.focusMode && (tabBox.value ?? .practice) == .practice
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 0) {
            if !hideSidebar {
                VStack(alignment: .leading, spacing: 0) {
                    AfradLogo()
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                    VStack(spacing: 2) {
                        ForEach(AppTab.allCases) { t in
                            let on = (tabBox.value ?? .practice) == t
                            Button(action: { tabBox.value = t }) {
                                HStack(spacing: 8) {
                                    Image(systemName: t.icon).frame(width: 20)
                                    Text(t.rawValue)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor.opacity(0.22) : Color.clear))
                                .foregroundColor(on ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    Spacer(minLength: 8)
                    VStack(spacing: 8) {
                        LevelBox(onHelp: { showGuide("level") })
                        DailyGoalBox(onHelp: { showGuide("goal") })
                    }
                    .padding(.horizontal, 12)
                    Spacer(minLength: 8)
                    HStack {
                        if let cur = session.current {
                            AvatarMenu(profile: cur)
                        } else {
                            Image(systemName: "person.circle")
                        }
                        Text(userName).lineLimit(1)
                        Spacer()
                        Button("Switch user") { session.signOut() }
                            .controlSize(.small)
                    }
                    .padding(10)
                }
                .frame(width: 200)
                Divider()
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        Divider()
        CopyrightLabel()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .onAppear {
            NSApp.applicationIconImage = AppIcon.make()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch tabBox.value ?? .practice {
        case .today:
            TodayView(onGo: { m in
                store.data.settings.mode = m
                tabBox.value = .practice
            })
        case .practice:
            PracticeView()
        case .stages:
            StagesView(onStart: { tabBox.value = .practice })
        case .progress:
            ProgressScreen()
        case .weakKeys:
            WeakKeysView()
        case .library:
            LibraryView(onUse: { tabBox.value = .practice })
        case .guide:
            GuideView(focus: guideFocus.value).id(guideFocus.value)
        }
    }
}


/// Sidebar box: minutes typed today against the daily goal. Sits between the tabs and the user.
struct DailyGoalBox: View {
    @EnvironmentObject var store: Store
    var onHelp: () -> Void = {}
    @StateObject private var showing = Box<Bool>(false)

    var body: some View {
        let goal = max(1, store.data.settings.dailyGoalMinutes)
        let done = store.secondsToday() / 60
        let reached = done >= Double(goal)
        let barColor = reached ? Color(nsColor: .systemGreen) : Color.accentColor
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY'S GOAL").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button(action: onHelp) {
                    Image(systemName: "questionmark.circle").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("How the daily goal works")
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(done))").font(.title2.weight(.semibold))
                Text("/ \(goal) min").font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: min(done / Double(goal), 1.0)).tint(barColor)
            if reached {
                Text("Goal reached \u{2713}").font(.caption).foregroundColor(Color(nsColor: .systemGreen))
            } else {
                Text("\(max(1, goal - Int(done))) min to go").font(.caption).foregroundColor(.secondary)
            }
            Button("Change goal") { showing.value = true }
                .buttonStyle(.link)
                .font(.caption)
                .popover(isPresented: Binding(get: { showing.value }, set: { showing.value = $0 }), arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Daily goal").font(.headline)
                        Stepper("\(goal) minutes a day", value: $store.data.settings.dailyGoalMinutes, in: 5...480, step: 5)
                    }
                    .padding(16)
                    .frame(width: 240)
                }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
    }
}


/// Sidebar box: your level, from the median speed of your last 30 sessions, lowered by accuracy.
struct LevelBox: View {
    @EnvironmentObject var store: Store
    var onHelp: () -> Void = {}

    private static let ranges = ["100+ WPM", "80\u{2013}99 WPM", "60\u{2013}79 WPM", "40\u{2013}59 WPM", "below 40 WPM"]

    private static let levels: [(Int, String, Color)] = [
        (100, "Pro Max", Color.purple),
        (80, "Pro", Color.yellow),
        (60, "Advanced", Color.orange),
        (40, "Intermediate", Color.green),
        (0, "Beginner", Color.blue)
    ]

    private struct Assessment {
        let wpm: Int
        let accuracy: Double
        let name: String
        let color: Color
        let held: Bool
        let count: Int
    }

    private var recent: [SessionRecord] {
        Array(store.data.history
            .filter { !$0.detail.hasPrefix("Warm-up") && !$0.detail.hasPrefix("Mistake replay") }
            .sorted { $0.date < $1.date }
            .suffix(30))
    }

    /// Median speed (so a few odd runs do not move it), then one level lower below 95% accuracy and two below 90%.
    private func assess(_ last: [SessionRecord]) -> Assessment? {
        guard last.count >= 10 else { return nil }
        let ws = last.map { $0.wpm }.sorted()
        let m = ws.count / 2
        let med = ws.count % 2 == 1 ? ws[m] : (ws[m - 1] + ws[m]) / 2
        let wpm = Int(med.rounded())
        let acc = last.map { $0.accuracy }.reduce(0, +) / Double(last.count)
        let base = LevelBox.levels.firstIndex(where: { wpm >= $0.0 }) ?? (LevelBox.levels.count - 1)
        let drop = acc < 90 ? 2 : (acc < 95 ? 1 : 0)
        let idx = min(LevelBox.levels.count - 1, base + drop)
        let lv = LevelBox.levels[idx]
        return Assessment(wpm: wpm, accuracy: acc, name: lv.1, color: lv.2, held: idx > base, count: last.count)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
    }

    /// Five bars, lowest level on the left. Filled = reached, empty = still to come.
    private func levelBars(current: String) -> some View {
        let n = LevelBox.levels.count
        let ci = LevelBox.levels.firstIndex(where: { $0.1 == current }) ?? (n - 1)
        return HStack(spacing: 4) {
            ForEach(0..<n, id: \.self) { k in
                let idx = n - 1 - k
                let lv = LevelBox.levels[idx]
                let state = idx < ci ? "not reached yet" : (idx == ci ? "your level" : "reached")
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(idx >= ci ? lv.2 : Color.clear)
                    RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.6), lineWidth: idx >= ci ? 0 : 1)
                }
                .frame(height: 8)
                .help("Level \(k + 1) of \(n) \u{00B7} \(lv.1) / \(LevelBox.ranges[idx]) \u{00B7} \(state)")
            }
        }
    }

    var body: some View {
        let last = recent
        let result = assess(last)
        return VStack(alignment: .leading, spacing: 6) {
            if let a = result {
                HStack {
                    Text(a.name)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(a.color))
                    Spacer()
                    Button(action: onHelp) {
                        Image(systemName: "questionmark.circle").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("How levels work")
                }
                levelBars(current: a.name)
                HStack(spacing: 8) {
                    tile("\(a.wpm)", "WPM")
                    tile(String(format: "%.1f%%", a.accuracy), "Accuracy")
                }
                if a.held {
                    Text("Held back by accuracy (needs 95%)").font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Text("YOUR LEVEL").font(.caption2).foregroundColor(.secondary)
                Text("Do 10 sessions to get your level (\(last.count) / 10).").font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
        .help("Median speed and average accuracy of your last 30 sessions")
    }
}
