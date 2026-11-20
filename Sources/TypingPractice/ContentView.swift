import SwiftUI
import AppKit

enum AppTab: String, CaseIterable, Identifiable {
    case today = "Daily Practice"
    case practice = "Practice"
    case stages = "Advanced"
    case progress = "Progress"
    case weakKeys = "Weak Spots"
    case library = "Library"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: return "target"
        case .practice: return "keyboard"
        case .stages: return "flag.checkered"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .weakKeys: return "exclamationmark.triangle"
        case .library: return "books.vertical"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var c: PracticeController
    @EnvironmentObject var session: AppSession
    var userName: String = ""
    @StateObject private var tabBox = Box<AppTab?>(.practice)

    private var hideSidebar: Bool {
        c.focusMode && (tabBox.value ?? .practice) == .practice
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 0) {
            if !hideSidebar {
                VStack(alignment: .leading, spacing: 0) {
                    AfradLogo()
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                    List(selection: $tabBox.value) {
                        ForEach(AppTab.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    .listStyle(.sidebar)
                    HStack {
                        if let cur = session.current {
                            AvatarMenu(profile: cur)
                        } else {
                            Image(systemName: "person.circle")
                        }
                        Text(userName).lineLimit(1)
                        Spacer()
                        Button("Switch user") { session.signOut() }
                            .controlSize(.small)
                    }
                    .padding(10)
                }
                .frame(width: 200)
                Divider()
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        Divider()
        CopyrightLabel()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .onAppear {
            NSApp.applicationIconImage = AppIcon.make()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch tabBox.value ?? .practice {
        case .today:
            TodayView(onGo: { m in
                store.data.settings.mode = m
                tabBox.value = .practice
            })
        case .practice:
            PracticeView()
        case .stages:
            StagesView(onStart: { tabBox.value = .practice })
        case .progress:
            ProgressScreen()
        case .weakKeys:
            WeakKeysView()
        case .library:
            LibraryView(onUse: { tabBox.value = .practice })
        }
    }
}
