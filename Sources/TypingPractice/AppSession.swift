import SwiftUI
import AppKit
import CryptoKit
import LocalAuthentication
import UniformTypeIdentifiers

struct ProfileInfo: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var file: String
    /// Optional password, stored only as a salted hash ("salt:hash", both base64).
    var pw: String? = nil
    /// Also unlock with Touch ID (only meaningful while a password is set).
    var touchID: Bool? = nil
    var locked: Bool { pw != nil }
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
    /// True when `message` is good news (shown in grey instead of red).
    @Published var messageOK = false
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
                messageOK = false
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
        messageOK = on
    }

    // MARK: Passwords (optional, per user)

    private static func hash(_ password: String, salt: Data) -> String {
        var d = salt + Data(password.utf8)
        for _ in 0..<20000 { d = Data(SHA256.hash(data: d)) }
        return d.base64EncodedString()
    }

    private static func makePw(_ password: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        let salt = Data(bytes)
        return salt.base64EncodedString() + ":" + hash(password, salt: salt)
    }

    func verify(_ p: ProfileInfo, password: String) -> Bool {
        guard let stored = (profiles.first(where: { $0.id == p.id }) ?? p).pw else { return true }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let salt = Data(base64Encoded: parts[0]) else { return false }
        return AppSession.hash(password, salt: salt) == parts[1]
    }

    private func notice(_ title: String, _ text: String = "") {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func askPasswords(_ title: String, _ text: String, labels: [String], ok: String = "OK") -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Cancel")
        let rowH: CGFloat = 32
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: rowH * CGFloat(labels.count)))
        var fields: [NSSecureTextField] = []
        for (i, l) in labels.enumerated() {
            let f = NSSecureTextField(frame: NSRect(x: 0, y: CGFloat(labels.count - 1 - i) * rowH + 4, width: 280, height: 24))
            f.placeholderString = l
            container.addSubview(f)
            fields.append(f)
        }
        alert.accessoryView = container
        alert.window.initialFirstResponder = fields.first
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return fields.map { $0.stringValue }
    }

    /// Asks for the current password; true when it is right (or the user has none).
    private func confirmPassword(_ p: ProfileInfo, why: String) -> Bool {
        guard p.locked else { return true }
        guard let v = askPasswords("Password for \(p.name)", why, labels: ["Password"]) else { return false }
        if verify(p, password: v[0]) { return true }
        notice("Wrong password")
        return false
    }

    /// Set or change a user's password.
    func changePassword(for p: ProfileInfo) {
        guard let i = profiles.firstIndex(where: { $0.id == p.id }) else { return }
        guard confirmPassword(profiles[i], why: "Enter your current password.") else { return }
        guard let v = askPasswords(profiles[i].locked ? "New password" : "Set a password",
                                   "If you forget it, it cannot be recovered.",
                                   labels: ["New password", "Repeat password"], ok: "Save") else { return }
        guard v[0].count >= 4 else { notice("Too short", "Use at least 4 characters."); return }
        guard v[0] == v[1] else { notice("The two passwords do not match"); return }
        profiles[i].pw = AppSession.makePw(v[0])
        saveIndex()
        if current?.id == p.id { current = profiles[i] }
        objectWillChange.send()
    }

    func removePassword(for p: ProfileInfo) {
        guard let i = profiles.firstIndex(where: { $0.id == p.id }), profiles[i].locked else { return }
        guard confirmPassword(profiles[i], why: "Enter your current password to remove it.") else { return }
        profiles[i].pw = nil
        profiles[i].touchID = nil
        saveIndex()
        if current?.id == p.id { current = profiles[i] }
        objectWillChange.send()
    }

    /// Signs in; a protected user must enter the password first.
    func requestSignIn(_ p: ProfileInfo) {
        let cur = profiles.first(where: { $0.id == p.id }) ?? p
        if cur.locked && cur.touchID == true && AppSession.touchIDAvailable {
            // Touch ID first; if it is cancelled or not recognised, fall back to the password box.
            runTouchID("Open \(cur.name)'s typing progress") { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    self.signIn(cur)
                } else if self.confirmPassword(cur, why: "Enter the password to open this user.") {
                    self.signIn(cur)
                }
            }
            return
        }
        guard confirmPassword(cur, why: "Enter the password to open this user.") else { return }
        signIn(cur)
    }

    // MARK: Touch ID (optional, on top of the password)

    /// True on Macs with Touch ID that has at least one fingerprint saved.
    static var touchIDAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    private var touchContext: LAContext? = nil

    /// Shows the system Touch ID prompt; the answer arrives on the main thread.
    private func runTouchID(_ reason: String, done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Use password\u{2026}"
        touchContext = ctx
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            DispatchQueue.main.async { done(false) }
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { done(success) }
        }
    }

    /// Turns Touch ID sign-in on or off for a user who has a password.
    func setTouchID(for p: ProfileInfo, on: Bool) {
        guard let i = profiles.firstIndex(where: { $0.id == p.id }), profiles[i].locked else { return }
        if !on {
            profiles[i].touchID = nil
            saveIndex()
            if current?.id == p.id { current = profiles[i] }
            objectWillChange.send()
            return
        }
        guard AppSession.touchIDAvailable else {
            notice("Touch ID is not available", "This Mac has no Touch ID, or no fingerprint is saved in System Settings.")
            return
        }
        guard confirmPassword(profiles[i], why: "Enter your password to turn on Touch ID.") else { return }
        let id = p.id
        runTouchID("Turn on Touch ID for \(p.name)") { [weak self] ok in
            guard let self = self, ok, let j = self.profiles.firstIndex(where: { $0.id == id }) else { return }
            self.profiles[j].touchID = true
            self.saveIndex()
            if self.current?.id == id { self.current = self.profiles[j] }
            self.objectWillChange.send()
        }
    }

    /// Deleting a protected user also needs the password.
    func canDelete(_ p: ProfileInfo) -> Bool {
        confirmPassword(p, why: "Enter the password to delete this user and all their data.")
    }

    // MARK: Profile pictures

    private var avatarCache: [UUID: NSImage] = [:]

    private func avatarURL(_ p: ProfileInfo) -> URL {
        profilesDir.appendingPathComponent(p.file + ".avatar.png")
    }

    /// The user's own picture, if they chose one.
    func avatar(for p: ProfileInfo) -> NSImage? {
        if let c = avatarCache[p.id] { return c }
        guard let img = NSImage(contentsOf: avatarURL(p)) else { return nil }
        avatarCache[p.id] = img
        return img
    }

    /// Lets the user pick a picture; it is cropped to a square and shrunk to 256 px.
    func chooseAvatar(for p: ProfileInfo) {
        let panel = NSOpenPanel()
        panel.title = "Choose a picture for \(p.name)"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let src = NSImage(contentsOf: url) else { return }
        let side: CGFloat = 256
        let w = src.size.width, h = src.size.height
        guard w > 0, h > 0 else { return }
        let s = min(w, h)
        let crop = NSRect(x: (w - s) / 2, y: (h - s) / 2, width: s, height: s)
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        src.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: crop, operation: .copy, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: avatarURL(p), options: .atomic)
        avatarCache[p.id] = out
        objectWillChange.send()
    }

    func removeAvatar(for p: ProfileInfo) {
        try? FileManager.default.removeItem(at: avatarURL(p))
        avatarCache[p.id] = nil
        objectWillChange.send()
    }

    // MARK: Users

    func signIn(_ p: ProfileInfo) {
        store?.flush()
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
        store?.flush()
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
            messageOK = false
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
        removeAvatar(for: p)
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
                        AvatarMenu(profile: p, size: 34)
                        if p.id == session.lastID {
                            Button(p.name) { session.requestSignIn(p) }
                                .keyboardShortcut(.defaultAction)
                                .controlSize(.large)
                                .frame(width: 240)
                        } else {
                            Button(p.name) { session.requestSignIn(p) }
                                .controlSize(.large)
                                .frame(width: 240)
                        }
                        if p.locked {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            if p.touchID == true && AppSession.touchIDAvailable {
                                Image(systemName: "touchid").foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            if session.canDelete(p) { confirm.value = p }
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
                Text(session.message).foregroundStyle(session.messageOK ? Color.secondary : Color.red).font(.callout)
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
            CopyrightLabel()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add() {
        session.addUser(name: newName.value)
        newName.value = ""
    }
}
