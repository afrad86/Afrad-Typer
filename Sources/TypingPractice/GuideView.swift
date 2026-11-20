import SwiftUI

/// "How it works": every rule the app follows, in one place. Sections open and close.
struct GuideView: View {
    @StateObject private var open: Box<Set<String>>

    init(focus: String) {
        _open = StateObject(wrappedValue: Box<Set<String>>([focus]))
    }

    private static let sections: [(String, String, [String])] = [
        ("level", "Your level and tag", [
            "The tag is based on the median speed of your last 30 sessions (warm-ups and mistake replays are not counted). It needs at least 10 sessions.",
            "Beginner: below 40 WPM. Intermediate: 40\u{2013}59. Advanced: 60\u{2013}79. Pro: 80\u{2013}99. Pro Max: 100+.",
            "Accuracy matters: if your average accuracy is below 95% you drop one level, below 90% two levels. The five bars under the tag show all levels: filled means reached, empty means still to come."
        ]),
        ("pass", "Passing a lesson", [
            "A lesson is passed when you reach the pass speed and accuracy set in Settings (default 30 WPM and 95%).",
            "After a pass, Tab or Return goes to the next lesson. If you did not pass, Tab repeats the lesson. Missed words can be replayed 5 times each.",
            "Weak-spot words mixed in do not count towards the pass mark."
        ]),
        ("stages", "Advanced stages", [
            "18 optional stages from 45 to 110 WPM: steps of 5 up to 80, then steps of 3. They never affect normal practice.",
            "Each lesson is 200 words. To unlock the next stage, finish 30 lessons where at least 90% reach the stage speed with 97% accuracy (96% from 86 WPM).",
            "The first stage lesson each day is a slow warm-up and does not count."
        ]),
        ("weak", "Weak keys and automatic practice", [
            "From your last 20 sessions the app finds weak keys, slow letter pairs and slow words, and mixes them into your lessons automatically.",
            "Trigram and tetragram lessons use only real, common letter groups taken from everyday English words."
        ]),
        ("keys", "Keys and shortcuts", [
            "Delete (backspace) fixes the last letter; mistakes still count against accuracy. In strict mode it only clears the red mark.",
            "Esc restarts the lesson. Tab goes to the next lesson after a pass. Return also continues.",
            "You can hide upcoming words (shown as grey blocks) to train looking ahead less."
        ]),
        ("pause", "Pause when you stop typing", [
            "If you stop for 3 seconds (change it in Settings: off, 2, 3, 5 or 10) the app pauses and shows \"Press any key to continue ...\".",
            "Paused time is not counted in WPM, daily minutes or the timed-test clock. A break reminder appears after 25 minutes of typing."
        ]),
        ("goal", "Daily goal, streak and calendar", [
            "Set your daily goal in minutes. Progress resets at midnight.",
            "Daily Practice splits the goal: warm-up 15%, lessons 40%, timed tests 25%, real text 20%.",
            "A streak counts consecutive days with practice. The 12-week calendar and the road-to-your-goal forecast appear in Progress; the forecast needs at least 5 practice days."
        ]),
        ("safe", "Backups, sync, passwords and Touch ID", [
            "A backup is saved automatically every week (the newest 8 are kept), and your data can sync through iCloud.",
            "Passwords are per user and cannot be recovered. They keep other people out of your profile but are not encryption.",
            "Touch ID is optional: once you have a password you can also unlock with Touch ID, from the picture menu."
        ])
    ]

    private func isOpen(_ id: String) -> Bool { open.value.contains(id) }

    private func toggle(_ id: String) {
        if open.value.contains(id) { open.value.remove(id) } else { open.value.insert(id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("How it works").font(.largeTitle.bold())
                Text("All the rules the app follows, in one place.").foregroundColor(.secondary)
                ForEach(GuideView.sections, id: \.0) { sec in
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { toggle(sec.0) }) {
                            HStack {
                                Text(sec.1).font(.headline)
                                Spacer()
                                Image(systemName: isOpen(sec.0) ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if isOpen(sec.0) {
                            ForEach(Array(sec.2.enumerated()), id: \.offset) { _, line in
                                Text(line).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10)))
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}
