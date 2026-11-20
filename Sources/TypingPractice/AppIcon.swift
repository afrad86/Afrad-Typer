import SwiftUI
import AppKit

enum AppIcon {
    /// The circular portrait logo, shipped inside the app as Logo.png.
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The "A" app icon, drawn in code so the Dock shows it while the app is running.
    static func make(size: CGFloat = 512) -> NSImage {
        if let l = logo { return l }
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
            if let l = AppIcon.logo {
                Image(nsImage: l)
                    .resizable()
                    .frame(width: 34, height: 34)
            } else {
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
            }
            Text("Afrad")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
    }
}

/// Copyright line shown in the sidebar and on the user screen.
struct CopyrightLabel: View {
    var body: some View {
        Text("\u{00A9} 2026 Hassan Afrad. All rights reserved.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// A round user picture with a thin orange ring; a plain person icon if no picture was chosen.
struct AvatarView: View {
    let image: NSImage?
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(red: 1.0, green: 0.596, blue: 0.0), lineWidth: 1.5))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Click the picture to choose or remove it, or to manage the password.
struct AvatarMenu: View {
    @EnvironmentObject var session: AppSession
    @StateObject private var open = Box<Bool>(false)
    let profile: ProfileInfo
    var size: CGFloat = 26

    /// A protected user can only be changed after signing in as that user.
    private var allowed: Bool { !profile.locked || session.current?.id == profile.id }
    private var signedInAsThis: Bool { session.current?.id == profile.id }

    /// Closes the pop-up first, then runs the action (some actions open their own windows).
    private func run(_ action: @escaping () -> Void) {
        open.value = false
        DispatchQueue.main.async { action() }
    }

    var body: some View {
        if allowed {
            Button {
                open.value.toggle()
            } label: {
                AvatarView(image: session.avatar(for: profile), size: size)
            }
            .buttonStyle(.plain)
            .help("Click to change your picture or password")
            .popover(isPresented: $open.value, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Choose picture\u{2026}") { run { session.chooseAvatar(for: profile) } }
                    if session.avatar(for: profile) != nil {
                        Button("Remove picture") { run { session.removeAvatar(for: profile) } }
                    }
                    if signedInAsThis {
                        Divider()
                        if profile.locked {
                            Button("Change password\u{2026}") { run { session.changePassword(for: profile) } }
                            Button("Remove password\u{2026}") { run { session.removePassword(for: profile) } }
                            if AppSession.touchIDAvailable {
                                Divider()
                                Button(profile.touchID == true ? "\u{2713} Also unlock with Touch ID" : "Also unlock with Touch ID") {
                                    run { session.setTouchID(for: profile, on: profile.touchID != true) }
                                }
                            }
                        } else {
                            Button("Set a password\u{2026}") { run { session.changePassword(for: profile) } }
                        }
                    }
                }
                .padding(14)
            }
        } else {
            AvatarView(image: session.avatar(for: profile), size: size)
        }
    }
}
