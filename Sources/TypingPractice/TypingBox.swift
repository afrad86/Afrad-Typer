import SwiftUI
import AppKit

/// The typing box with the text and the result card. It watches the per-key ticks; the rest of the screen does not.
struct TypingBox: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var c: PracticeController
    @ObservedObject var live: LiveTick

    private var settings: AppSettings { store.data.settings }

    // MARK: Typing area

    /// Tells the controller the real width, font and size so lines can be filled by measuring the letters.
    private func fitLines(width: CGFloat) {
        let usable = width - 56 - 6   // padding on both sides, plus a little slack so a line never has to shrink
        let font = settings.font, size = CGFloat(settings.textSize)
        DispatchQueue.main.async { c.setLayout(width: usable, font: font, size: size) }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .textBackgroundColor))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.25))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(c.visibleLines, id: \.self) { r in
                    Text(c.attributed(r))
                        .font(TypingFont.font(settings.font, size: CGFloat(settings.textSize)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if c.paused && c.result == nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.45))
                    Text("Press any key to continue ...")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(Capsule().strokeBorder(Color.accentColor))
                }
            }

            if let r = c.result {
                resultCard(r)
            } else if !c.started {
                VStack {
                    Spacer()
                    Text("Start typing to begin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: max(c.result != nil ? 440 : 300, CGFloat(70 + Int(Double(settings.textSize) * 1.7) * settings.linesShown)))
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { fitLines(width: geo.size.width) }
                    .onChange(of: geo.size.width) { w in fitLines(width: w) }
                    .onChange(of: settings.textSize) { _ in fitLines(width: geo.size.width) }
                    .onChange(of: settings.font) { _ in fitLines(width: geo.size.width) }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func resultCard(_ r: SessionResult) -> some View {
        let title: String
        let color: Color
        if let p = r.passed {
            title = r.stage ? (p ? "Stage lesson passed" : "Stage lesson missed") : (p ? "Lesson passed" : "Not quite — try again")
            color = p ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
        } else {
            title = r.timedOut ? "Time's up" : "Done"
            color = Color.accentColor
        }
        let primary = r.stage ? (r.passed == true ? "Continue" : "Try again") : ((r.passed == false) ? "Retry" : (r.passed == true ? "Next lesson" : "New round"))
        let consText = r.consistency > 0 ? String(format: "%.0f%%", r.consistency) : "–"
        let rawText = String(format: "%.0f", r.rawWPM)
        let reachedGoal = r.wpm >= Double(settings.targetWPM)
        return VStack(spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(color)
            if reachedGoal {
                Text("You hit your goal speed of \(settings.targetWPM) WPM!")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .systemGreen))
            }
            if let note = r.note {
                Text(note)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            HStack(spacing: 30) {
                StatTile(title: "WPM (net)", value: String(format: "%.0f", r.wpm))
                StatTile(title: "Accuracy", value: String(format: "%.1f%%", r.accuracy))
                StatTile(title: "Time", value: String(format: "%.0f s", r.seconds))
            }
            .frame(maxWidth: 460)
            if !c.missedWords.isEmpty {
                VStack(spacing: 6) {
                    Text("Words you slipped on: " + c.missedWords.joined(separator: ", "))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                    Button("Retype these words 5 times") { c.startReplay() }
                }
            }
            Text("Raw \(rawText) WPM  ·  Consistency \(consText)")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(primary) { c.proceed() }
                    .buttonStyle(.borderedProminent)
                if r.passed != nil {
                    Button("Repeat this one") { c.retry() }
                }
            }
            Text(r.passed == true ? "Return or Tab = \(primary.lowercased())  ·  Esc = restart" : "Return = \(primary.lowercased())  ·  Tab or Esc = restart")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor).opacity(0.97)))
    }

}

/// The live numbers above the options (WPM, accuracy, time, pace caret), redrawn with each key and clock tick.
struct LiveStatsRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var c: PracticeController
    @ObservedObject var live: LiveTick

    private var settings: AppSettings { store.data.settings }

    // MARK: Live stats

    var body: some View {
        let wpmColor: Color = c.showThreshold && c.started
            ? (c.liveWPM >= Double(settings.minWPM) ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
            : Color.primary
        let accColor: Color = c.showThreshold && c.totalKeys > 0
            ? (c.liveAccuracy >= Double(settings.minAccuracy) ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
            : Color.primary
        let timeText: String = c.timeLimit > 0
            ? String(format: "%.0f s", max(0, c.timeLimit - c.elapsed))
            : String(format: "%.0f s", c.elapsed)
        let timeShown = c.paused ? timeText + " \u{23F8}" : timeText
        return HStack(spacing: 12) {
            StatTile(title: "WPM", value: String(format: "%.0f", c.liveWPM), color: wpmColor)
            StatTile(title: "Accuracy", value: String(format: "%.1f%%", c.liveAccuracy), color: accColor)
            StatTile(title: "Average WPM (this run)", value: c.avgWPM == 0 ? "–" : String(format: "%.0f", c.avgWPM))
            StatTile(title: c.timeLimit > 0 ? "Time left" : "Time", value: timeShown)
            if let d = c.paceDelta {
                StatTile(
                    title: "vs pace caret (chars)",
                    value: d >= 0 ? "+\(d)" : "\(d)",
                    color: d >= 0 ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
                )
            }
        }
    }}
