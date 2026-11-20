import SwiftUI
import AppKit

enum AppIcon {
    /// The "A" app icon, drawn in code so the Dock shows it while the app is running.
    static func make(size: CGFloat = 512) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
            let path = NSBezierPath(roundedRect: inset, xRadius: size * 0.22, yRadius: size * 0.22)
            let top = NSColor(calibratedWhite: 0.31, alpha: 1)
            let bottom = NSColor(calibratedWhite: 0.25, alpha: 1)
            if let gradient = NSGradient(starting: top, ending: bottom) {
                gradient.draw(in: path, angle: -60)
            }
            let font = NSFont.systemFont(ofSize: size * 0.62, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.596, blue: 0.0, alpha: 1)]
            let text = NSAttributedString(string: "A", attributes: attrs)
            let sz = text.size()
            text.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
            return true
        }
    }
}

/// The "Afrad" logo shown at the top-left of the window.
struct AfradLogo: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.31), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("A")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.596, blue: 0.0))
            }
            .frame(width: 30, height: 30)
            Text("Afrad")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
    }
}
