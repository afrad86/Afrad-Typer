import SwiftUI

struct StagesView: View {
    @EnvironmentObject var store: Store
    var onStart: () -> Void

    private var settings: AppSettings { store.data.settings }

    private func start(_ t: Int) {
        store.data.settings.stageSelected = t
        store.data.settings.mode = .stages
        onStart()
    }

    var body: some View {
        let cleared = settings.stageCleared
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Advanced stages to \(StageRules.targets.last ?? 110) WPM").font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 6) {
                    Text("The rules").font(.headline)
                    Text("This track is optional and separate from your normal practice. Free practice (Daily Practice, Practice and the rest) never depends on it. Each stage lesson is \(settings.stageMinWords) words. To unlock the next stage you must finish \(settings.stageMinLessons) lessons, and at least 90% of your \(settings.stageMinLessons) counted lessons must reach the stage speed (a miss stays counted until a later pass cancels it: each new pass cancels one earlier miss, and a new miss is simply added) with at least \(settings.stageAccuracyLow)% accuracy (\(settings.stageAccuracyHigh)% from 86 WPM). The first stage lesson each day is a short slow warm-up that does not count. It does not have to happen in one day: take as many days as you need. Only lessons done here count.")
                        .foregroundStyle(.secondary)
                    Text("Stage lessons use everyday words with a few capitals and punctuation marks, so every attempt is comparable. Use normal Lessons (with auto-focus on your weak spots) and timed tests to train between stage lessons; they never affect your stage.")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))

                HStack(spacing: 12) {
                    Picker("My current stage", selection: Binding<Int>(
                        get: { settings.stageSelected },
                        set: { t in
                            store.data.settings.stageCleared = StageRules.previous(of: t)
                            store.data.settings.stageSelected = t
                        }
                    )) {
                        ForEach(StageRules.targets, id: \.self) { t in
                            Text("\(t) WPM").tag(t)
                        }
                    }
                    .frame(width: 240)
                    Text("Already faster than the early stages? Pick the stage you want to start from. Earlier stages count as cleared.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Stepper("Lessons needed per stage: \(settings.stageMinLessons)", value: $store.data.settings.stageMinLessons, in: 1...200, step: 5)
                    HStack(spacing: 8) {
                        Text("Lesson length")
                        ForEach([50, 100, 200], id: \.self) { n in
                            OptionChip(title: "\(n) words", selected: settings.stageMinWords == n) { store.data.settings.stageMinWords = n }
                        }
                    }
                }

                HStack(spacing: 24) {
                    Stepper("Accuracy up to 85 WPM: \(settings.stageAccuracyLow)%", value: $store.data.settings.stageAccuracyLow, in: 90...100)
                    Stepper("Accuracy from 86 WPM: \(settings.stageAccuracyHigh)%", value: $store.data.settings.stageAccuracyHigh, in: 90...100)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Ramp capitals and punctuation up with the stage (recommended: plain words below 60 WPM, real-text level near 100)", isOn: $store.data.settings.stageAutoMix)
                    HStack(spacing: 28) {
                        mixSlider("Capital letters", value: $store.data.settings.stageCapitals)
                        mixSlider("Punctuation", value: $store.data.settings.stagePunctuation)
                    }
                    .disabled(settings.stageAutoMix)
                    .opacity(settings.stageAutoMix ? 0.5 : 1)
                }
                Toggle("Daily slow warm-up before stage lessons (pace caret at about 70% of your average)", isOn: $store.data.settings.warmupEnabled)

                VStack(spacing: 10) {
                    ForEach(StageRules.targets, id: \.self) { t in
                        stageRow(t, cleared: cleared)
                    }
                }
            }
            .padding(24)
        }
    }

    private func mixSlider(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text("\(title): \(value.wrappedValue)%")
                .monospacedDigit()
                .frame(width: 180, alignment: .leading)
            Slider(
                value: Binding<Double>(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...30,
                step: 1
            )
            .frame(width: 200)
        }
    }

    private func stageRow(_ t: Int, cleared: Int) -> some View {
        let isCleared = t <= cleared
        let frontier = StageRules.next(after: cleared) ?? (StageRules.targets.last ?? 110)
        let unlocked = t <= frontier
        let rep = store.stageDayReport(target: t)
        let icon = isCleared ? "checkmark.circle.fill" : (unlocked ? "flag.fill" : "lock.fill")
        let color: Color = isCleared ? Color(nsColor: .systemGreen) : (unlocked ? Color.accentColor : Color.secondary)
        let detail: String = isCleared
            ? "Cleared"
            : (unlocked
                ? "Unlocked — " + rep.text
                : "Locked — clear the \(StageRules.previous(of: t)) WPM stage first")
        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(t) WPM stage").font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(isCleared ? "Replay" : "Start lesson") { start(t) }
                .disabled(!unlocked)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(unlocked ? 0.10 : 0.04)))
        .opacity(unlocked ? 1 : 0.6)
    }
}
