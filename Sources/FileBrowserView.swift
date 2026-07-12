import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject var galleryManager: GalleryManager
    @State private var currentURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [FileEntry] = []
    @State private var selectedFileIds: Set<UUID> = []
    @State private var lastSelectedId: UUID?

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
                        .background(selectedFileIds.contains(entry.id) ? Color.accentColor.opacity(0.5) : Color.clear)
                        .overlay(selectedFileIds.contains(entry.id) ? Rectangle().frame(width: 3).foregroundColor(.accentColor) : nil, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleTap(entry: entry)
                        }
                        .contextMenu {
                            if !entry.isDirectory {
                                let targets = selectedFileIds.contains(entry.id) ? selectedFileIds : [entry.id]
                                Menu("Add To Gallery (\(targets.count))") {
                                    ForEach(galleryManager.galleries.indices, id: \.self) { i in
                                        Button(galleryManager.galleryName(at: i)) {
                                            for id in targets {
                                                if let e = entries.first(where: { $0.id == id }) {
                                                    Task {
                                                        await ImageLoader.shared.loadAndSend(url: e.url, to: galleryManager.galleries[i])
                                                    }
                                                }
                                            }
                                        }
                                    }
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

    private func handleTap(entry: FileEntry) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        let cmd = NSEvent.modifierFlags.contains(.command)

        if shift, let lastId = lastSelectedId {
            if let curIdx = entries.firstIndex(where: { $0.id == entry.id }),
               let lastIdx = entries.firstIndex(where: { $0.id == lastId }) {
                let range = min(lastIdx, curIdx)...max(lastIdx, curIdx)
                selectedFileIds = Set(entries[range].map(\.id))
            }
        } else if cmd {
            if selectedFileIds.contains(entry.id) {
                selectedFileIds.remove(entry.id)
            } else {
                selectedFileIds.insert(entry.id)
            }
        } else {
            selectedFileIds = [entry.id]
        }
        lastSelectedId = entry.id

        if entry.isDirectory {
            if !shift && !cmd {
                currentURL = entry.url
                selectedFileIds.removeAll()
                lastSelectedId = nil
                loadEntries()
            }
        } else {
            loadImage(entry)
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
        selectedFileIds.removeAll()
        lastSelectedId = nil
        loadEntries()
    }

    private func loadImage(_ entry: FileEntry) {
        let path = entry.url.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let activeStore = galleryManager.activeStore
        if let existing = activeStore.getItemByPath(path) {
            activeStore.selectedImageId = existing.id
            PreviewStore.shared.setPreview(image: existing.image, path: path)
            return
        }
        Task {
            let image = await Task.detached { () -> NSImage? in
                ImageViewer.loadImage(from: entry.url)
            }.value
            if let image = image {
                await MainActor.run {
                    PreviewStore.shared.setPreview(image: image, path: path)
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
