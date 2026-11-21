import SwiftUI
import AppKit
import CoreText

/// Whether the welcome screen is showing. It opens by itself the first time the app runs on a computer.
final class WelcomeState: ObservableObject {
    static let shared = WelcomeState()
    @Published var show: Bool
    init() { show = !UserDefaults.standard.bool(forKey: "welcomeSeen") }
}

enum BundledFonts {
    /// Makes the bundled Pacifico font (SIL Open Font License) available to the app.
    static func register() {
        if let url = Bundle.main.url(forResource: "Pacifico-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct WelcomeView: View {
    var onClose: () -> Void
    @StateObject private var dontShow = Box<Bool>(true)

    private let yellow = Color(red: 1.0, green: 0.82, blue: 0.25)
    private let teal = Color(red: 0.37, green: 0.84, blue: 0.71)

    private static let links: [(String, String, String)] = [
        ("Typing.com", "Beginner course: finger placement, home row, every key", "https://www.typing.com"),
        ("TypingClub", "Short guided lessons with a virtual hand on screen", "https://www.typingclub.com"),
        ("Keybr.com", "Adaptive practice that builds up the keys one by one", "https://www.keybr.com")
    ]

    private func open(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    private func finish() {
        if dontShow.value { UserDefaults.standard.set(true, forKey: "welcomeSeen") }
        onClose()
    }

    private func keycap(_ ch: String, _ color: Color?) -> some View {
        Text(ch)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color ?? Color.clear, lineWidth: 2))
    }

    private func keyRow(_ keys: [String], colors: [Color?]) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<keys.count, id: \.self) { i in
                keycap(keys[i], colors[i])
            }
        }
    }

    private var keyboard: some View {
        let purple = Color(red: 0.78, green: 0.55, blue: 1.0)
        let green = Color(red: 0.37, green: 0.72, blue: 0.47)
        let orange = Color(red: 0.94, green: 0.53, blue: 0.24)
        let gold = Color(red: 0.91, green: 0.83, blue: 0.30)
        let none: Color? = nil
        return VStack(spacing: 6) {
            Text("WHAT \"TOUCH TYPING\" MEANS: EIGHT FINGERS ON THE HOME ROW, EYES ON THE SCREEN")
                .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
            keyRow(["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], colors: Array(repeating: none, count: 10))
            keyRow(["A", "S", "D", "F", "G", "H", "J", "K", "L", ";"],
                   colors: [purple, green, orange, gold, none, none, gold, orange, green, purple])
            keyRow(["Z", "X", "C", "V", "B", "N", "M"], colors: Array(repeating: none, count: 7))
            Text("Rest on A S D F and J K L ;   \u{00B7}   Feel the bumps on F and J   \u{00B7}   Thumbs on the space bar")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.10)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text("Welcome to").font(.callout).foregroundColor(.secondary)
                    Text("Afrad")
                        .font(.custom("Pacifico-Regular", size: 56))
                        .foregroundColor(yellow)
                        .padding(.top, 2)
                    Text("TOUCH TYPING")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(6)
                        .padding(.top, -2)
                    Text("Please read this first. It takes one minute.")
                        .font(.callout).foregroundColor(.secondary)
                        .padding(.top, 10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("This app is for people who already touch type.")
                        .font(.headline).foregroundColor(yellow)
                    Text("It trains speed and accuracy. It does not teach you where your fingers go or which finger presses which key. If you still look at the keyboard and type with two fingers, learn the basics first (links below), then come back.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(yellow.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(yellow.opacity(0.45), lineWidth: 1))

                keyboard

                VStack(alignment: .leading, spacing: 8) {
                    Text("New to touch typing? Learn it first, free")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(teal)
                    ForEach(0..<WelcomeView.links.count, id: \.self) { i in
                        let l = WelcomeView.links[i]
                        Button(action: { open(l.2) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(l.0).font(.headline)
                                    Text(l.1).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Open in browser \u{2197}").font(.caption).foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    Button(action: finish) {
                        HStack(spacing: 10) {
                            Text("Yes, I can touch type")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(red: 0.16, green: 0.13, blue: 0.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14).fill(
                                LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.40), Color(red: 1.0, green: 0.79, blue: 0.16)],
                                               startPoint: .top, endPoint: .bottom)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button("Not yet, remind me next time") { onClose() }
                        .buttonStyle(.link)
                        .font(.callout)
                    Toggle("Don't show this again", isOn: $dontShow.value)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                .padding(.top, 4)

                Divider()
                Text("Copyright \u{00A9} 2026 Hassan Afrad. All rights reserved.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(28)
        }
        .frame(width: 660, height: 720)
    }
}
