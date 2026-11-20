import SwiftUI
import AppKit

struct ProfileInfo: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var file: String
}

/// Holds the list of users and the currently signed-in user's Store and PracticeController.
/// Every user has their own data file, so progress, stages and settings are completely separate.
/// With iCloud sync on, the data lives in iCloud Drive so your Macs share (and merge) it.
final class AppSession: ObservableObject {
    @Published var profiles: [ProfileInfo] = []
    @Published var lastID: UUID? = nil
    @Published var current: ProfileInfo? = nil
    @Published var store: Store? = nil
    @Published var controller: PracticeController? = nil
    @Published var message = ""
    @Published var syncOn = false

    private let localBase: URL
    private let cloudParent: URL
    private let cloudBase: URL
    private static let syncKey = "afradSyncICloud"

    private var base: URL { syncOn ? cloudBase : localBase }
    private var indexURL: URL { base.appendingPathComponent("profiles.json") }
    private var profilesDir: URL { base.appendingPathComponent("profiles", isDirectory: true) }

    private struct Index: Codable {
        var profiles: [ProfileInfo]
        var lastID: UUID?
    }

    init() {
        let fm = FileManager.default
        localBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypingPractice", isDirectory: true)
        cloudParent = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        cloudBase = cloudParent.appendingPathComponent("Afrad Typer", isDirectory: true)

        var wantSync = UserDefaults.standard.bool(forKey: AppSession.syncKey)
        if wantSync && !fm.fileExists(atPath: cloudParent.path) { wantSync = false }
        syncOn = wantSync

        try? fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        if let idx = readIndex(base) {
            profiles = idx.profiles
            lastID = idx.lastID
        } else {
            // First launch of this version: your existing data becomes the user "Afrad".
            let legacy = localBase.appendingPathComponent("store.json")
            if fm.fileExists(atPath: legacy.path) {
                let p = ProfileInfo(name: "Afrad", file: "\(UUID().uuidString).json")
                try? fm.copyItem(at: legacy, to: profilesDir.appendingPathComponent(p.file))
                profiles = [p]
                lastID = p.id
                saveIndex()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reloadIndex()
        }
    }

    // MARK: Index files

    private func readIndex(_ dir: URL) -> Index? {
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent("profiles.json")) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: raw)
    }

    private func writeIndex(_ idx: Index, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("profiles", isDirectory: true), withIntermediateDirectories: true)
        if let raw = try? JSONEncoder().encode(idx) {
            try? raw.write(to: dir.appendingPathComponent("profiles.json"), options: .atomic)
        }
    }

    private func saveIndex() {
        writeIndex(Index(profiles: profiles, lastID: lastID), to: base)
    }

    /// Picks up users added on the other Mac (while at the user screen).
    private func reloadIndex() {
        guard syncOn, current == nil, let idx = readIndex(base) else { return }
        profiles = idx.profiles
        if lastID == nil { lastID = idx.lastID }
    }

    /// Copies users from one folder into another; users with the same name are merged.
    private func migrate(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let s = readIndex(src) else { return }
        try? fm.createDirectory(at: dst.appendingPathComponent("profiles", isDirectory: true), withIntermediateDirectories: true)
        var d = readIndex(dst) ?? Index(profiles: [], lastID: nil)
        func load(_ url: URL) -> StoreData? {
            guard let raw = try? Data(contentsOf: url) else { return nil }
            return try? Store.decoder.decode(StoreData.self, from: raw)
        }
        for p in s.profiles {
            let srcFile = src.appendingPathComponent("profiles").appendingPathComponent(p.file)
            if let i = d.profiles.firstIndex(where: { $0.name.lowercased() == p.name.lowercased() }) {
                let dstFile = dst.appendingPathComponent("profiles").appendingPathComponent(d.profiles[i].file)
                let a = load(dstFile) ?? StoreData()
                let b = load(srcFile) ?? StoreData()
                let (m, _) = Store.merge(a, b)
                if let raw = try? Store.encoder.encode(m) { try? raw.write(to: dstFile, options: .atomic) }
            } else {
                let dstFile = dst.appendingPathComponent("profiles").appendingPathComponent(p.file)
                try? fm.removeItem(at: dstFile)
                try? fm.copyItem(at: srcFile, to: dstFile)
                d.profiles.append(p)
            }
        }
        if d.lastID == nil { d.lastID = s.lastID }
        writeIndex(d, to: dst)
    }

    // MARK: Sync

    func setSync(_ on: Bool) {
        guard on != syncOn else { return }
        signOut()
        let fm = FileManager.default
        if on {
            guard fm.fileExists(atPath: cloudParent.path) else {
                message = "iCloud Drive is not turned on for this Mac, so sync is unavailable."
                objectWillChange.send()
                return
            }
            try? fm.createDirectory(at: cloudBase, withIntermediateDirectories: true)
            migrate(from: localBase, to: cloudBase)
        } else {
            migrate(from: cloudBase, to: localBase)
        }
        syncOn = on
        UserDefaults.standard.set(on, forKey: AppSession.syncKey)
        if let idx = readIndex(base) {
            profiles = idx.profiles
            lastID = idx.lastID
        }
        message = on ? "Sync is on. Turn it on at the user screen on your other Mac too." : ""
    }

    // MARK: Users

    func signIn(_ p: ProfileInfo) {
        controller?.shutdown()
        let s = Store(fileURL: profilesDir.appendingPathComponent(p.file), syncing: syncOn)
        let c = PracticeController(store: s)
        store = s
        controller = c
        current = p
        s.autoBackup(label: p.name)
        lastID = p.id
        saveIndex()
    }

    func signOut() {
        controller?.shutdown()
        controller = nil
        store = nil
        current = nil
    }

    func addUser(name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if profiles.contains(where: { $0.name.lowercased() == n.lowercased() }) {
            message = "A user called \(n) already exists."
            return
        }
        let p = ProfileInfo(name: n, file: "\(UUID().uuidString).json")
        profiles.append(p)
        saveIndex()
        message = ""
        signIn(p)
    }

    func deleteUser(_ p: ProfileInfo) {
        profiles.removeAll { $0.id == p.id }
        try? FileManager.default.removeItem(at: profilesDir.appendingPathComponent(p.file))
        if lastID == p.id { lastID = profiles.first?.id }
        saveIndex()
    }
}

struct RootView: View {
    @EnvironmentObject var session: AppSession

    var body: some View {
        if let s = session.store, let c = session.controller, let p = session.current {
            ContentView(userName: p.name)
                .environmentObject(s)
                .environmentObject(c)
                .id(p.id)
        } else {
            ProfilePickerView()
        }
    }
}

struct ProfilePickerView: View {
    @EnvironmentObject var session: AppSession
    @StateObject private var newName = Box<String>("")
    @StateObject private var confirm = Box<ProfileInfo?>(nil)

    var body: some View {
        VStack(spacing: 18) {
            AfradLogo()
            Text("Who is practising?").font(.largeTitle.bold())
            if session.profiles.isEmpty {
                Text("Create the first user to begin.").foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(session.profiles) { p in
                    HStack {
                        if p.id == session.lastID {
                            Button(p.name) { session.signIn(p) }
                                .keyboardShortcut(.defaultAction)
                                .controlSize(.large)
                                .frame(width: 240)
                        } else {
                            Button(p.name) { session.signIn(p) }
                                .controlSize(.large)
                                .frame(width: 240)
                        }
                        Button {
                            confirm.value = p
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete this user and all their data")
                    }
                }
            }
            Divider().frame(width: 320)
            HStack {
                TextField("New user name", text: $newName.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { add() }
                Button("Add user") { add() }
                    .disabled(newName.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            VStack(spacing: 4) {
                Toggle("Sync my progress between Macs with iCloud Drive", isOn: Binding<Bool>(
                    get: { session.syncOn },
                    set: { session.setSync($0) }
                ))
                Text("Turn this on at the user screen on both Macs, using the same user names. Progress merges automatically. Needs iCloud Drive enabled; macOS may ask for permission the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if !session.message.isEmpty {
                Text(session.message).foregroundStyle(.red).font(.callout)
            }
            if let p = confirm.value {
                VStack(spacing: 8) {
                    Text("Delete \(p.name) and all of their progress? This cannot be undone.")
                    HStack {
                        Button("Delete") {
                            session.deleteUser(p)
                            confirm.value = nil
                        }
                        Button("Cancel") { confirm.value = nil }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add() {
        session.addUser(name: newName.value)
        newName.value = ""
    }
}
