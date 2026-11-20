import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: Store
    var onUse: () -> Void
    @StateObject private var ui = LibraryUI()


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Library").font(.largeTitle.bold())
                Text("Add articles to practise on. The app downloads the page, keeps the readable text, and splits it into lessons.")
                    .foregroundStyle(.secondary)

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
