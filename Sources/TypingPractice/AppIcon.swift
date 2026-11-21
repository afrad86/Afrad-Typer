import SwiftUI
import AppKit

enum AppIcon {
    /// The circular portrait logo, shipped inside the app as Logo.png.
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The "A" app icon, drawn in code so the Dock shows it while the app is running.
    /// Drawn once per launch and reused.
    static let cached: NSImage = make()

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
        HStack {
            Spacer()
            if let l = AppIcon.logo {
                Image(nsImage: l)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
            } else {
                Text("Afrad")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.25))
            }
            Spacer()
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
            .help("Click to manage your photo and password")
            .popover(isPresented: $open.value, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PHOTO").font(.caption2).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        if session.avatar(for: profile) != nil {
                            Button("Change photo") { run { session.chooseAvatar(for: profile) } }
                            Text("\u{00B7}").foregroundColor(.secondary)
                            Button("Remove") { run { session.removeAvatar(for: profile) } }
                        } else {
                            Button("Add photo") { run { session.chooseAvatar(for: profile) } }
                        }
                    }
                    .buttonStyle(.link)
                    if signedInAsThis {
                        Divider()
                        Text("PASSWORD").font(.caption2).foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            if profile.locked {
                                Button("Change password") { run { session.changePassword(for: profile) } }
                                Text("\u{00B7}").foregroundColor(.secondary)
                                Button("Remove") { run { session.removePassword(for: profile) } }
                            } else {
                                Button("Set a password") { run { session.changePassword(for: profile) } }
                            }
                        }
                        .buttonStyle(.link)
                        if profile.locked && AppSession.touchIDAvailable {
                            Divider()
                            HStack {
                                Text("Unlock with Touch ID").font(.callout)
                                Spacer(minLength: 16)
                                Text(profile.touchID == true ? "On \u{2713}" : "Off")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { run { session.setTouchID(for: profile, on: profile.touchID != true) } }
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
