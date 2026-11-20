import SwiftUI

/// Progress screen: an estimated date for reaching your goal speed, and a 12-week practice calendar.
struct RoadAndCalendar: View {
    @EnvironmentObject var store: Store
    private let cal = Calendar.current

    private var counted: [SessionRecord] {
        store.data.history
            .filter { !$0.detail.hasPrefix("Warm-up") && !$0.detail.hasPrefix("Mistake replay") }
            .sorted { $0.date < $1.date }
    }

    private enum Outlook {
        case reached
        case few(Int)
        case spread
        case flat
        case far(Double)
        case date(Date, Double)
    }

    /// Straight-line trend of your daily average speed over the last 6 weeks.
    private func outlook(target: Double) -> (Double, Outlook) {
        let hs = counted
        let last = hs.suffix(10)
        let cur = last.isEmpty ? 0 : last.map { $0.wpm }.reduce(0, +) / Double(last.count)
        if cur >= target { return (cur, .reached) }
        let since = Date().addingTimeInterval(-42 * 86400)
        var byDay: [Date: [Double]] = [:]
        for r in hs where r.date >= since {
            byDay[cal.startOfDay(for: r.date), default: []].append(r.wpm)
        }
        let days = byDay.keys.sorted()
        if days.count < 5 { return (cur, .few(5 - days.count)) }
        let t0 = days[0]
        var pts: [(Double, Double)] = []
        for d in days {
            let x = Double(cal.dateComponents([.day], from: t0, to: d).day ?? 0)
            let ys = byDay[d] ?? []
            pts.append((x, ys.reduce(0, +) / Double(max(1, ys.count))))
        }
        if (pts.last?.0 ?? 0) < 10 { return (cur, .spread) }
        let n = Double(pts.count)
        let mx = pts.map { $0.0 }.reduce(0, +) / n
        let my = pts.map { $0.1 }.reduce(0, +) / n
        let sxx = pts.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
        let sxy = pts.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +)
        let perDay = sxx > 0 ? sxy / sxx : 0
        let perWeek = perDay * 7
        if perWeek < 0.3 { return (cur, .flat) }
        let needDays = (target - cur) / perDay
        if needDays > 730 { return (cur, .far(perWeek)) }
        return (cur, .date(Date().addingTimeInterval(needDays * 86400), perWeek))
    }

    private var minutesByDay: [Date: Double] {
        var m: [Date: Double] = [:]
        for r in store.data.history { m[cal.startOfDay(for: r.date), default: 0] += r.seconds / 60 }
        return m
    }

    private var bestStreak: Int {
        let days = minutesByDay.keys.sorted()
        var best = 0
        var run = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            road.frame(maxWidth: .infinity, alignment: .topLeading)
            calendar.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var road: some View {
        let target = Double(max(1, store.data.settings.targetWPM))
        let (cur, out) = outlook(target: target)
        var message = ""
        switch out {
        case .reached:
            message = "You are at \(Int(target)) WPM or more on average. Goal reached!"
        case .few(let n):
            message = "Practise on \(n) more day\(n == 1 ? "" : "s") and I will estimate your date."
        case .spread:
            message = "Practise over a longer stretch (at least 10 days apart) and I will estimate your date."
        case .flat:
            message = "Your average has been flat over the last 6 weeks, so there is no date yet. Short, accurate sessions most days are what move it."
        case .far(let w):
            message = String(format: "At your recent pace (%.1f WPM a week) it would take more than 2 years. More regular practice will change that.", w)
        case .date(let d, let w):
            let f = DateFormatter()
            f.dateFormat = "LLLL yyyy"
            message = String(format: "At your recent pace (+%.1f WPM a week) you reach \(Int(target)) WPM around ", w) + f.string(from: d) + "."
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Road to \(Int(target)) WPM").font(.headline)
            Text("Current average \(Int(cur.rounded())) (last 10 sessions)  →  goal \(Int(target))")
            ProgressView(value: min(cur / target, 1.0))
            Text(message).font(.callout).foregroundStyle(.secondary)
            Text("This is an estimate from your own trend, not a promise.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private var calendar: some View {
        let goal = Double(max(1, store.data.settings.dailyGoalMinutes))
        let by = minutesByDay
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        let start = cal.date(byAdding: .day, value: -(mondayOffset + 77), to: today) ?? today
        return VStack(alignment: .leading, spacing: 8) {
            Text("Practice calendar").font(.headline)
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<12, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            cell(day: cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start, today: today, by: by, goal: goal)
                        }
                    }
                }
            }
            Text("Last 12 weeks, one square per day. Darker orange means more minutes; the darkest means you reached your daily goal. Current streak \(store.streak) day(s)  ·  best \(bestStreak).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private func cell(day: Date, today: Date, by: [Date: Double], goal: Double) -> some View {
        if day > today {
            Color.clear.frame(width: 18, height: 18)
        } else {
            let m = by[day] ?? 0
            let level = m <= 0 ? 0 : (m < goal / 2 ? 1 : (m < goal ? 2 : 3))
            let opacity: Double = level == 0 ? 0.0 : (level == 1 ? 0.35 : (level == 2 ? 0.65 : 1.0))
            RoundedRectangle(cornerRadius: 4)
                .fill(level == 0 ? Color.secondary.opacity(0.15) : Color.orange.opacity(opacity))
                .frame(width: 18, height: 18)
                .help("\(day.formatted(date: .abbreviated, time: .omitted)): \(Int(m.rounded())) min")
        }
    }
}
