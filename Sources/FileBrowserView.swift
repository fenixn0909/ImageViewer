import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject var store: ImageStore
    @State private var currentURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [FileEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentURL.path == "/")

                Text(currentURL.lastPathComponent).font(.headline).lineLimit(1)

                Spacer()

                Button("Choose...") { chooseFolder() }
                    .font(.system(size: 11))
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder" : "photo")
                                .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                                .frame(width: 20)
                            Text(entry.name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if entry.isDirectory {
                                currentURL = entry.url
                                loadEntries()
                            } else {
                                loadImage(entry)
                            }
                        }
                        .contextMenu {
                            if !entry.isDirectory {
                                Button("Add To Gallery") {
                                    Task { await ImageLoader.shared.loadAndSend(url: entry.url) }
                                }
                            }
                        }
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            if let savedPath = UserDefaults.standard.string(forKey: "fileBrowserLastPath"),
               FileManager.default.fileExists(atPath: savedPath) {
                currentURL = URL(fileURLWithPath: savedPath)
            }
            loadEntries()
        }
        .onChange(of: currentURL) { newURL in
            UserDefaults.standard.set(newURL.path, forKey: "fileBrowserLastPath")
        }
    }

    private func loadEntries() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            )
            entries = urls.compactMap { url -> FileEntry? in
                guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else { return nil }
                if isDir { return FileEntry(name: url.lastPathComponent, url: url, isDirectory: true) }
                guard isImageFile(url) else { return nil }
                return FileEntry(name: url.lastPathComponent, url: url, isDirectory: false)
            }
            .sorted { l, r in
                if l.isDirectory && !r.isDirectory { return true }
                if !l.isDirectory && r.isDirectory { return false }
                return l.name.localizedStandardCompare(r.name) == .orderedAscending
            }
        } catch {
            entries = []
        }
    }

    private func goBack() {
        currentURL = currentURL.deletingLastPathComponent()
        loadEntries()
    }

    private func loadImage(_ entry: FileEntry) {
        let path = entry.url.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        if let existing = store.getItemByPath(path) {
            store.selectedImageId = existing.id
            store.clearPreview()
            return
        }
        Task {
            let image = await Task.detached { () -> NSImage? in
                ImageViewer.loadImage(from: entry.url)
            }.value
            if let image = image {
                await MainActor.run {
                    store.setPreview(image: image, path: path)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                currentURL = url
                loadEntries()
            }
        }
    }
}

private struct FileEntry: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
}
