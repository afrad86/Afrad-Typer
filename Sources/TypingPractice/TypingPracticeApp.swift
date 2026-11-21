import SwiftUI
import AppKit

/// Sizes the window to the screen it opens on (about 92% of the free width, 94% of the free height),
/// so a small laptop gets a window that fits and a big screen gets a big window. Runs once per launch.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let w = v.window, let screen = w.screen ?? NSScreen.main else { return }
            let vf = screen.visibleFrame
            let width = min(vf.width * 0.92, 1700)
            let height = min(vf.height * 0.94, 1250)
            let frame = NSRect(x: vf.midX - width / 2, y: vf.midY - height / 2, width: width, height: height)
            w.setFrame(frame, display: true, animate: false)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct TypingPracticeApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var updates = UpdateState.shared
    @StateObject private var welcome = WelcomeState.shared

    init() { BundledFonts.register() }

    /// The minimum width never exceeds what the screen can show.
    private static var minWidth: CGFloat {
        let w = NSScreen.main?.visibleFrame.width ?? 1440
        return min(1040, max(760, w - 40))
    }

    var body: some Scene {
        WindowGroup("Afrad Typer") {
            RootView()
                .environmentObject(session)
                .frame(minWidth: TypingPracticeApp.minWidth, minHeight: 480)
                .background(WindowFitter())
                .onAppear { Updater.peek() }
                .sheet(isPresented: $welcome.show) { WelcomeView(onClose: { welcome.show = false }) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Updater.peek() }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Getting started") { welcome.show = true }
                Button("How it works") { NotificationCenter.default.post(name: .openGuide, object: nil) }
                Divider()
                Button(updates.latest.map { "Update available v\($0)\u{2026}" } ?? "Check for Updates\u{2026}") { Updater.check() }
                Button("About Afrad Typer") { Updater.about() }
            }
        }
    }
}
