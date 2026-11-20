import SwiftUI

@main
struct TypingPracticeApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup("Afrad Typer") {
            RootView()
                .environmentObject(session)
                .frame(minWidth: 1040, minHeight: 780)
        }
    }
}
