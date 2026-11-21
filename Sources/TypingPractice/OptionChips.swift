import SwiftUI
import AppKit

enum Brand {
    static let orange = Color(red: 0.94, green: 0.53, blue: 0.24)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.25)
}

/// A rounded choice button. Selected = orange; hovering tints orange.
struct OptionChip: View {
    let title: String
    let selected: Bool
    var disabled: Bool = false
    let action: () -> Void
    @StateObject private var hover = Box<Bool>(false)

    private var fill: Color {
        if selected { return hover.value ? Color(red: 0.96, green: 0.60, blue: 0.34) : Brand.orange }
        return hover.value ? Brand.orange.opacity(0.35) : Color.secondary.opacity(0.18)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? Color(red: 0.16, green: 0.09, blue: 0.0) : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }
}

/// One horizontal row of options: a label on the left, the choices beside it.
struct OptionRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 84, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { content }
                    .padding(.vertical, 1)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A tab shape with rounded top corners.
struct TabShape: Shape {
    var radius: CGFloat = 10
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Sheet-style tabs that sit on top of the typing area: Lessons, Timed, Passages, Numbers & symbols.
struct ModeTabs: View {
    @EnvironmentObject var store: Store

    private static let order: [PracticeMode] = [.drills, .timed, .passages, .symbols]

    private var current: PracticeMode {
        switch store.data.settings.mode {
        case .drills, .smart, .weakKeys, .pairs, .slowWords: return .drills
        default: return store.data.settings.mode
        }
    }

    private var items: [(PracticeMode, String)] {
        var list: [(PracticeMode, String)] = [(.drills, "Lessons"), (.timed, "Timed"), (.passages, "Passages"), (.symbols, "Numbers & symbols")]
        if store.data.settings.mode == .stages { list.append((.stages, "Advanced stage")) }
        return list
    }

    private func tab(_ m: PracticeMode, _ title: String) -> some View {
        let on = current == m
        return Button(action: { store.data.settings.mode = m }) {
            Text(title)
                .font(.system(size: 13.5, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Color.primary : Color.secondary)
                .padding(.horizontal, 20)
                .padding(.top, on ? 11 : 9)
                .padding(.bottom, 8)
                .background(TabShape().fill(on ? Color(nsColor: .textBackgroundColor) : Color.secondary.opacity(0.12)))
                .overlay(TabShape().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .overlay(
                    VStack(spacing: 0) {
                        if on { Rectangle().fill(Brand.yellow).frame(height: 3) }
                        Spacer(minLength: 0)
                    }
                    .clipShape(TabShape())
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shortcuts: some View {
        HStack {
            ForEach(0..<4, id: \.self) { i in
                Button("") { store.data.settings.mode = ModeTabs.order[i] }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<items.count, id: \.self) { i in
                tab(items[i].0, items[i].1)
            }
            Spacer()
            Text("Click a tab, or press \u{2318}1 to \u{2318}4")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.leading, 14)
        .background(shortcuts)
    }
}
