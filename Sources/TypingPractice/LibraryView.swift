import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: Store
    var onUse: () -> Void
    @StateObject private var ui = LibraryUI()


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Library").font(.largeTitle.bold())
                Text("Pick a story to practise, or add your own articles. The app downloads a page, keeps the readable text, and splits it into lessons.")
                    .foregroundStyle(.secondary)

                if !Books.all.isEmpty { storiesSection }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add from a web address").font(.headline)
                    HStack {
                        TextField("https://…", text: $ui.urlText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addURL() }
                        Button(ui.busy ? "Loading…" : "Add") { addURL() }
                            .disabled(ui.busy || ui.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !ui.message.isEmpty {
                        Text(ui.message).font(.callout).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or paste text").font(.headline)
                    TextField("Title (optional)", text: $ui.pasteTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                    TextEditor(text: $ui.pasteText)
                        .font(.body)
                        .frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Button("Add pasted text") {
                        if store.addPastedPassage(title: ui.pasteTitle, text: ui.pasteText) {
                            ui.pasteTitle = ""
                            ui.pasteText = ""
                            ui.message = "Added."
                        } else {
                            ui.message = "Paste at least a sentence or two."
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your passages").font(.headline)
                    ForEach(store.data.passages) { p in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.body.weight(.medium)).lineLimit(2)
                                Text("\(p.url) · \(p.text.count) characters")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Practise") {
                                store.data.settings.selectedPassage = p.id
                                store.data.settings.mode = .passages
                                onUse()
                            }
                            Button("Delete", role: .destructive) {
                                store.deletePassage(p.id)
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(24)
        }
    }

    private var storiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stories").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(Books.all) { b in
                    let open = ui.openBook == b.id
                    Button { ui.openBook = open ? nil : b.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(b.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(2)
                            Text(b.author).font(.caption).foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Text(b.level)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8).padding(.vertical, 1)
                                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                                Text("\(b.parts.count) parts").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(open ? Brand.slate : Color.secondary.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(open ? Brand.slateLine : Color.secondary.opacity(0.2)))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let id = ui.openBook, let b = Books.all.first(where: { $0.id == id }) {
                Text(b.title).font(.callout.weight(.semibold)).foregroundColor(.secondary).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(0..<b.parts.count, id: \.self) { i in
                        let pid = Books.uuid(b.id, i)
                        HStack(spacing: 12) {
                            Text("\(i + 1)").foregroundColor(.secondary).frame(width: 26, alignment: .leading)
                            Text(b.parts[i].title).fontWeight(store.data.settings.selectedPassage == pid ? .semibold : .regular)
                            Spacer()
                            Text("\(b.parts[i].text.split(separator: " ").count) words").font(.caption).foregroundColor(.secondary)
                            Button(store.data.settings.selectedPassage == pid ? "Selected" : "Practise") {
                                store.data.settings.selectedPassage = pid
                                store.data.settings.mode = .passages
                                onUse()
                            }
                        }
                        .padding(.vertical, 8)
                        if i < b.parts.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            }
        }
    }

    private func addURL() {
        let text = ui.urlText
        ui.busy = true
        ui.message = ""
        Task { @MainActor in
            do {
                try await store.addPassage(urlString: text)
                ui.urlText = ""
                ui.message = "Added."
            } catch {
                ui.message = error.localizedDescription
            }
            ui.busy = false
        }
    }
}
