import SwiftUI

/// A tiny observable holder used instead of @State (the newest SDK implements @State as a macro,
/// which the Command Line Tools cannot expand).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

final class LibraryUI: ObservableObject {
    @Published var urlText = ""
    @Published var busy = false
    @Published var message = ""
    @Published var pasteTitle = ""
    @Published var pasteText = ""
}
