import SwiftUI
import AppKit

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
    }
}

struct PracticeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var c: PracticeController

    private var settings: AppSettings { store.data.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                topRow
                if !c.focusMode {
                    LiveStatsRow(live: c.live)
                    if isLessonFamily { lessonPanel }
                    settingsSection
                    aheadRow
                    infoBlock
                }
                VStack(spacing: 0) {
                    if !c.focusMode { ModeTabs() }
                    TypingBox(live: c.live)
                }
                if !c.focusMode {
                    Text("Click the text area, then just type  ·  Backspace fixes mistakes  ·  Esc restarts  ·  Return continues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear {
            c.active = true
            c.installMonitor()
            c.newSession()
        }
        .onDisappear { c.active = false }
        .overlay(
            Group {
                if c.breakDue { breakCard }
            }
        )
        .onChange(of: store.data.settings.configKey) { _ in c.newSession() }
        .alert("Stage unlocked!", isPresented: Binding<Bool>(
            get: { c.unlockMessage != nil },
            set: { if !$0 { c.unlockMessage = nil } }
        )) {
            Button("Continue") { c.unlockMessage = nil }
        } message: {
            Text(c.unlockMessage ?? "")
        }
    }

    private var aheadRow: some View {
        HStack(spacing: 14) {
            Text("Words ahead").font(.callout.weight(.semibold))
            Picker("Words ahead", selection: $store.data.settings.hideAhead) {
                Text("See all").tag(0)
                Text("Hide the next word").tag(1)
                Text("Hide the next two words").tag(2)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            Spacer()
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 10) {
            if settings.mode == .timed || settings.mode == .passages || settings.mode == .symbols || settings.mode == .stages {
                optionsBar
            }
            if c.settingsOpen {
                extrasBar
            }
        }
    }

    private var breakCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.stand").font(.system(size: 44))
            Text("Time for a short break").font(.title.bold())
            Text("You have typed for about \(settings.breakMinutes) minutes. Take your hands off the keyboard, roll your shoulders back, shake out your wrists and look at something far away for 20 seconds. Sit tall with your wrists level and relaxed.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("I'm back") { c.dismissBreak() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
    }

    private static let lessonFamily: [PracticeMode] = [.drills, .smart, .weakKeys, .pairs, .slowWords]

    private var isLessonFamily: Bool { PracticeView.lessonFamily.contains(settings.mode) }

    private var modePicker: some View {
        Picker("Mode", selection: Binding<PracticeMode>(
            get: { isLessonFamily ? .drills : settings.mode },
            set: { store.data.settings.mode = $0 }
        )) {
            ForEach([PracticeMode.drills, .timed, .passages, .symbols] + (settings.mode == .stages ? [PracticeMode.stages] : [])) { m in
                Text(m == .stages ? "Advanced stage lesson" : m.rawValue).tag(m)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 230)
    }

    private var topRow: some View {
        HStack(spacing: 14) {
            if !c.focusMode {
                lessonRow
            }
            Spacer()
            if !c.focusMode {
                Toggle("Sounds", isOn: $store.data.settings.sounds)
                    .toggleStyle(.switch)
                    .accentColor(Brand.slateLine)
            }
            if c.focusMode {
                Picker("Words ahead", selection: $store.data.settings.hideAhead) {
                    Text("See all words").tag(0)
                    Text("Hide the next word").tag(1)
                    Text("Hide the next two words").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)
            }
            HStack(spacing: 4) {
                Button { store.data.settings.textSize = max(16, settings.textSize - 2) } label: { Text("A−") }
                    .keyboardShortcut("-", modifiers: .command)
                    .help("Smaller text (Cmd -)")
                Button { store.data.settings.textSize = min(64, settings.textSize + 2) } label: { Text("A+") }
                    .keyboardShortcut("=", modifiers: .command)
                    .help("Bigger text (Cmd +)")
                Menu {
                    ForEach(TypingFont.all, id: \.key) { f in
                        Button {
                            store.data.settings.font = f.key
                        } label: {
                            Text(f.name + (f.hint.isEmpty ? "" : "  (\(f.hint))") + (settings.font == f.key ? "  \u{2713}" : ""))
                        }
                    }
                } label: {
                    Text("Font: \(TypingFont.name(settings.font))")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose the font of the typing text")
            }
            Button {
                if c.focusMode { c.showOptions.toggle() } else { c.settingsOpen.toggle() }
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .help("Mode options, capitals, punctuation, pace and breaks")
            .popover(
                isPresented: Binding<Bool>(
                    get: { c.focusMode && c.showOptions },
                    set: { c.showOptions = $0 }
                ),
                arrowEdge: .bottom
            ) {
                VStack(spacing: 14) {
                    modePicker
                    if isLessonFamily { lessonPanel }
                    optionsBar
                    extrasBar
                    infoBlock
                }
                .padding(20)
                .frame(width: 820)
            }
            Button {
                c.focusMode.toggle()
            } label: {
                Label(c.focusMode ? "Exit focus" : "Focus mode", systemImage: c.focusMode ? "eye" : "eye.slash")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Hide everything except the text (Cmd+Shift+F)")
        }
    }

    // MARK: Options

    @ViewBuilder
    private var optionsBar: some View {
        switch settings.mode {
        case .drills:
            EmptyView()
        case .timed:
            modePanel {
                OptionRow("Duration") {
                    ForEach([15, 30, 60, 120, 180], id: \.self) { n in
                        OptionChip(title: "\(n) s", selected: settings.timedSeconds == n) { store.data.settings.timedSeconds = n }
                    }
                }
                Divider()
                poolRow
            }
        case .passages:
            modePanel {
                OptionRow("Passage") {
                    Picker("Passage", selection: passageBinding) {
                        ForEach(store.data.passages) { p in
                            Text(p.title).tag(p.id)
                        }
                        ForEach(Books.all) { b in
                            Section(b.title) {
                                ForEach(0..<b.parts.count, id: \.self) { i in
                                    Text(b.parts[i].title).tag(Books.uuid(b.id, i))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 360)
                }
                Divider()
                OptionRow("Threshold") {
                    Stepper("WPM: \(settings.minWPM)", value: $store.data.settings.minWPM, in: 5...200, step: 5)
                    Stepper("Accuracy: \(settings.minAccuracy)%", value: $store.data.settings.minAccuracy, in: 50...100)
                }
            }
        case .stages:
            VStack(spacing: 6) {
                Text("Advanced stage \(settings.stageSelected) WPM. Each lesson is \(settings.stageMinWords) words. Finish \(settings.stageMinLessons) lessons, in any number of days; at least 90% of your \(settings.stageMinLessons) counted lessons must reach \(settings.stageSelected) WPM at \(Int(settings.stageAccuracy(for: settings.stageSelected)))%+ accuracy before the next stage unlocks.")
                    .foregroundStyle(.secondary)
                Text(store.stageDayReport(target: settings.stageSelected).text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Leave advanced stages (free practice)") { store.data.settings.mode = .drills }
            }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 720)
        case .smart, .weakKeys, .slowWords, .pairs:
            EmptyView()
        case .symbols:
            modePanel {
                poolRow
                Divider()
                OptionRow("Length") {
                    Stepper("Words per round: \(settings.wordCount)", value: $store.data.settings.wordCount, in: 10...300, step: 5)
                }
            }
        }
    }

    /// The tidy panel around a mode's options.
    private func modePanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
            .accentColor(Brand.slateLine)
    }

    private var poolRow: some View {
        OptionRow("Words") {
            ForEach([200, 500, 1000, 2000, 3000], id: \.self) { n in
                OptionChip(title: "Top \(n)", selected: settings.wordPool == n) { store.data.settings.wordPool = n }
            }
        }
    }

    private var usesWordPool: Bool {
        let m = settings.mode
        return m == .smart || m == .timed || m == .weakKeys || m == .pairs || m == .slowWords || m == .symbols
    }

    private var extrasBar: some View {
        VStack(spacing: 10) {
            breakRow
            if settings.mode != .passages && settings.mode != .symbols && settings.mode != .stages {
                HStack(spacing: 28) {
                    percentSlider("Capital letters", value: $store.data.settings.capitalPercent)
                    percentSlider("Punctuation", value: $store.data.settings.punctuationPercent)
                }
            }
            HStack(spacing: 20) {
                Stepper("Words per round: \(settings.wordCount)", value: $store.data.settings.wordCount, in: 10...300, step: 5)
                    .frame(width: 240)
                    .disabled(settings.mode == .timed || settings.mode == .stages || settings.mode == .drills)
                Stepper("Lines shown: \(settings.linesShown)", value: $store.data.settings.linesShown, in: 3...8)
                    .frame(width: 190)
            }
            HStack(spacing: 20) {
                Stepper(
                    settings.paceWPM == 0 ? "Pace caret: off" : "Pace caret: \(settings.paceWPM) WPM",
                    value: $store.data.settings.paceWPM,
                    in: 0...250,
                    step: 5
                )
                .frame(width: 210)
                Button("Pace = my average + 5%") { setSmartPace() }
                Picker("Pause when idle", selection: $store.data.settings.afkSeconds) {
                    Text("Pause: off").tag(0)
                    ForEach([2, 3, 5, 10], id: \.self) { n in
                        Text("Pause after \(n) s").tag(n)
                    }
                }
                .frame(width: 190)
                .help("The clock stops when you stop typing for this long, and carries on with your next key")
                Toggle("Strict: stop at mistakes", isOn: $store.data.settings.strictMode)
                Toggle("Coach adjusts pace", isOn: $store.data.settings.autoPace)
                    .help("The pace caret speeds up after clean, fast rounds and eases off after sloppy ones")
                if usesWordPool {
                    Picker("Word pool", selection: $store.data.settings.wordPool) {
                        ForEach([200, 500, 1000, 2000, 3000], id: \.self) { n in
                            Text("Top \(n)").tag(n)
                        }
                    }
                    .frame(width: 190)
                }
            }
        }
    }

    private var breakRow: some View {
        HStack(spacing: 20) {
            Toggle("Break reminders", isOn: $store.data.settings.breakReminder)
            Stepper("Every \(settings.breakMinutes) min", value: $store.data.settings.breakMinutes, in: 15...45, step: 5)
                .frame(width: 170)
                .disabled(!settings.breakReminder)
        }
    }

    private func percentSlider(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text("\(title): \(value.wrappedValue)%")
                .monospacedDigit()
                .frame(width: 180, alignment: .leading)
            Slider(
                value: Binding<Double>(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...100,
                step: 5
            )
            .frame(width: 200)
        }
    }

    private func setSmartPace() {
        let recent = store.data.history.suffix(10)
        guard !recent.isEmpty else { return }
        let avg = recent.map { $0.wpm }.reduce(0, +) / Double(recent.count)
        let target = Int((avg * 1.05 / 5).rounded()) * 5
        store.data.settings.paceWPM = min(250, max(5, target))
    }

    private var assessmentText: String {
        switch settings.mode {
        case .smart:
            return "The coach assesses your keys, letter pairs and whole words, drills your weakest areas first, then finishes with a timed test. Press Return after each round to move on."
        case .weakKeys:
            let k = LessonBuilder.weakKeys(store.keyStats(last: 20), limit: 6).map { $0.uppercased() }
            return k.isEmpty ? "Not enough data yet. Practise a few lessons so the app can find your weak keys." : "Assessment: your weakest keys are " + k.joined(separator: ", ") + "."
        case .pairs:
            let p = LessonBuilder.slowPairs(store.pairStats(last: 20), limit: 6).map { $0.uppercased() }
            return p.isEmpty ? "Not enough data yet. Practise a few lessons so the app can find your slow pairs." : "Assessment: your slowest letter pairs are " + p.joined(separator: ", ") + "."
        case .slowWords:
            let w = LessonBuilder.slowWords(store.wordStats(last: 20), baseline: store.baselineMs(last: 20), limit: 8)
            return w.isEmpty ? "Not enough data yet. Practise a few lessons so the app can find your slow words." : "Assessment: your slowest words are " + w.joined(separator: ", ") + "."
        default:
            return ""
        }
    }

    private var lessonPanel: some View {
        let isCustom = settings.source == .custom
        let standard = settings.mode == .drills
        return VStack(spacing: 12) {
            if standard {
                VStack(spacing: 0) {
                    OptionRow("Source") {
                        ForEach(DrillSource.allCases) { s in
                            OptionChip(title: s.rawValue, selected: settings.source == s) { store.data.settings.source = s }
                        }
                    }
                    Divider()
                    OptionRow("Scope") {
                        ForEach([50, 100, 150, 200, 500, 1000, 2000, 3000], id: \.self) { n in
                            OptionChip(title: "Top \(n)", selected: settings.scope == n, disabled: isCustom) { store.data.settings.scope = n }
                        }
                    }
                    Divider()
                    OptionRow("Generator") {
                        ForEach(GeneratorStyle.allCases) { g in
                            OptionChip(title: g.rawValue, selected: settings.generator == g) { store.data.settings.generator = g }
                        }
                        Stepper("Combination: \(settings.itemsPerLesson)", value: $store.data.settings.itemsPerLesson, in: 1...50)
                            .help("How many items go into one lesson")
                        Stepper("Repetition: \(settings.repetition)", value: $store.data.settings.repetition, in: 1...30)
                            .help("How many times the chain repeats")
                    }
                    Divider()
                    OptionRow("Threshold") {
                        Stepper("WPM: \(settings.minWPM)", value: $store.data.settings.minWPM, in: 5...200, step: 5)
                        Stepper("Accuracy: \(settings.minAccuracy)%", value: $store.data.settings.minAccuracy, in: 50...100)
                        Toggle("Mixed order", isOn: $store.data.settings.mixedOrder)
                            .help("Shuffle the Top-N items once, so lesson 1 is not only the most frequent ones")
                        Toggle("Auto-focus on my weak spots", isOn: $store.data.settings.autoFocus)
                            .help("The app finds your weak keys, slow pairs and slow words and adds extra practice on them to every lesson")
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 44) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Assessment").font(.headline)
                        Text(assessmentText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 560, alignment: .leading)
                        Button("Back to standard lessons") { store.data.settings.mode = .drills }
                        if settings.mode == .smart {
                            Picker("Timed test length", selection: $store.data.settings.timedSeconds) {
                                ForEach([15, 30, 60, 120, 180], id: \.self) { n in
                                    Text("\(n) s").tag(n)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                        }
                    }
                }
            }
            if standard && isCustom {
                TextField("Type your own words, separated by spaces", text: $store.data.settings.customWords)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 700)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accentColor(Brand.slateLine)
    }

    private var passageBinding: Binding<UUID> {
        Binding<UUID>(
            get: {
                store.data.settings.selectedPassage ?? store.allPassages.first?.id ?? UUID()
            },
            set: { store.data.settings.selectedPassage = $0 }
        )
    }

    // MARK: Header

    private var lessonRow: some View {
        HStack(spacing: 8) {
            if c.canNavigateLessons {
                Button { c.stepLesson(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
            }
            Text(c.lessonLabel)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            if c.canNavigateLessons {
                Button { c.stepLesson(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            if c.showThreshold {
                Text("Pass: \(settings.minWPM) WPM · \(settings.minAccuracy)%")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoBlock: some View {
        VStack(spacing: 4) {
            if !c.coachLine.isEmpty {
                Text(c.coachLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !c.infoLine.isEmpty {
                Text(c.infoLine)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }


}
