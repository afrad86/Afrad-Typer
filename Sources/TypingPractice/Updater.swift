import AppKit

extension Notification.Name {
    static let openGuide = Notification.Name("AfradTyperOpenGuide")
}

/// "Check for Updates": reads release/version.json from the project's GitHub page, and if a newer version exists,
/// downloads it, replaces this app and reopens it. Your data is not touched.
enum Updater {
    private static let base = "https://raw.githubusercontent.com/afrad86/Afrad-Typer/main/release/"
    private static var busy = false

    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    private static func isNewer(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func alert(_ title: String, _ text: String, buttons: [String] = ["OK"]) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        for b in buttons { a.addButton(withTitle: b) }
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    static func about() {
        _ = alert("Afrad Typer", "Version \(current)\nCopyright \u{00A9} 2026 Hassan Afrad.")
    }

    static func check() {
        if busy { return }
        busy = true
        guard let url = URL(string: base + "version.json?t=\(Int(Date().timeIntervalSince1970))") else { busy = false; return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latest = obj["version"] as? String else {
                    busy = false
                    _ = alert("Could not check for updates", "Check your internet connection and try again.")
                    return
                }
                if !isNewer(latest, current) {
                    busy = false
                    _ = alert("You're up to date", "Afrad Typer \(current) is the latest version.")
                    return
                }
                let go = alert("Update available: \(latest)",
                               "You have \(current). The app will download the update, replace itself and reopen. Your progress is kept.",
                               buttons: ["Install and Restart", "Later"])
                if !go { busy = false; return }
                let file = (obj["mac"] as? String) ?? (base + "Afrad-Typer.zip")
                install(from: file)
            }
        }.resume()
    }

    private static func fail(_ text: String) {
        DispatchQueue.main.async {
            busy = false
            _ = alert("Update failed", text)
        }
    }

    private static func install(from file: String) {
        guard let url = URL(string: file) else { fail("The update address is not valid."); return }
        let appPath = Bundle.main.bundlePath
        guard FileManager.default.isWritableFile(atPath: (appPath as NSString).deletingLastPathComponent) else {
            fail("This app is in a folder you cannot change. Move it to Applications or your Desktop and try again.")
            return
        }
        NSApp.mainWindow?.title = "Afrad Typer \u{2014} downloading update\u{2026}"
        URLSession.shared.downloadTask(with: url) { tmp, _, err in
            guard let tmp = tmp, err == nil else { fail("The download did not finish. Check your internet connection."); return }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("AfradTyperUpdate-\(UUID().uuidString)")
            let zip = work.appendingPathComponent("update.zip")
            let out = work.appendingPathComponent("new")
            do {
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try fm.moveItem(at: tmp, to: zip)
            } catch { fail("Could not save the update."); return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, out.path]
            do { try p.run(); p.waitUntilExit() } catch { fail("Could not unpack the update."); return }
            guard p.terminationStatus == 0,
                  let name = (try? fm.contentsOfDirectory(atPath: out.path))?.first(where: { $0.hasSuffix(".app") }) else {
                fail("The downloaded update looks damaged."); return
            }
            let newApp = out.appendingPathComponent(name).path
            let script = """
            #!/bin/sh
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            /usr/bin/ditto "\(newApp)" "\(appPath).new" && rm -rf "\(appPath)" && mv "\(appPath).new" "\(appPath)"
            /usr/bin/xattr -cr "\(appPath)"
            /usr/bin/open "\(appPath)"
            rm -rf "\(work.path)"
            """
            let sh = work.appendingPathComponent("update.sh")
            do { try script.write(to: sh, atomically: true, encoding: .utf8) } catch { fail("Could not prepare the update."); return }
            let r = Process()
            r.executableURL = URL(fileURLWithPath: "/bin/sh")
            r.arguments = ["-c", "nohup /bin/sh \"\(sh.path)\" >/dev/null 2>&1 &"]
            do { try r.run() } catch { fail("Could not start the update."); return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }.resume()
    }
}
