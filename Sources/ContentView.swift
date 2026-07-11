import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var galleryManager: GalleryManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var previewStore = PreviewStore.shared
    @State private var activeStoreRef: ImageStore = ImageStore.shared
    @State private var refreshToken: Int = 0
    @State private var isTargeted = false
    @State private var errorToShow: ImageLoadError?
    @State private var zoomPercent: Int = 100
    @State private var showDeleteConfirm = false

    private var store: ImageStore { galleryManager.activeStore }
    var displayItem: ImageItem? {
        if galleryManager.selectedTab == 0 {
            return previewStore.previewItem
        } else {
            _ = refreshToken
            return activeStoreRef.getSelectedImage()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
            
            HSplitView {
                VStack(spacing: 0) {
                    tabBar

                    if galleryManager.selectedTab == 0 {
                        FileBrowserView()
                    } else {
                        let galleryIndex = galleryManager.selectedTab - 1
                        GallerySidebar(store: galleryManager.galleries[galleryIndex])
                    }
                }
                .frame(minWidth: 150, maxWidth: 360)

                ZStack {
                    if let item = displayItem {
                        ImagePreview(item: item, onZoomChange: { zoomPercent = $0 })
                    } else {
                        emptyStateView
                    }
                }
                .frame(minWidth: 360, minHeight: 220)
            }
            .frame(maxHeight: .infinity)

            FileInfoBar(item: displayItem, zoomPercent: displayItem != nil ? zoomPercent : nil)
        }
        .onReceive(store.$lastError) { error in errorToShow = error }
        .alert("Error", isPresented: .init(get: { errorToShow != nil }, set: { if !$0 { errorToShow = nil } })) {
            Text(errorToShow?.localizedDescription ?? "Unknown error")
        }
        .alert("Delete Gallery", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { executeGalleryRemoval() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let last = galleryManager.galleries.last {
                Text("Delete \(galleryManager.galleryName(at: galleryManager.galleries.count - 1))? It contains \(last.images.count) image(s).")
            }
        }
        .background(arrowKeyButtons)
        .onAppear {
            if galleryManager.selectedTab > 0, galleryManager.selectedTab - 1 < galleryManager.galleries.count {
                activeStoreRef = galleryManager.galleries[galleryManager.selectedTab - 1]
            }
            _ = AnimationPanelController.shared
            if PreferencesStore.shared.showPaveOnStartup {
                PavePanelController.shared.window?.makeKeyAndOrderFront(nil)
            }
            setupTabKeyMonitor()
            
            // Automatically trigger the click/restoration sequence on startup
            triggerAutomaticStartupClick()
        }
        .onChange(of: galleryManager.selectedTab) { newTab in
            if newTab != 0 {
                PreviewStore.shared.clearPreview()
                activeStoreRef = galleryManager.galleries[newTab - 1]
            }
        }
        .onReceive(activeStoreRef.objectWillChange) { _ in
            refreshToken &+= 1
        }
        // Permanently record the stable path of the image being displayed
        .onChange(of: displayItem?.filePath) { newPath in
            if let path = newPath {
                UserDefaults.standard.set(path, forKey: "lastViewedImagePath")
            }
        }
    }

    /// Simulates a user clicking the last viewed tab and image once app resources load
    private func triggerAutomaticStartupClick() {
        guard let lastPath = UserDefaults.standard.string(forKey: "lastViewedImagePath"),
              FileManager.default.fileExists(atPath: lastPath) else { return }
        
        let currentTab = galleryManager.selectedTab
        
        if currentTab == 0 {
            // Browser Tab: Allow the file system layout a split second to settle, then load preview
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let url = URL(fileURLWithPath: lastPath)
                Task {
                    let image = await Task.detached { () -> NSImage? in
                        ImageViewer.loadImage(from: url)
                    }.value
                    if let image = image {
                        await MainActor.run {
                            PreviewStore.shared.setPreview(image: image, path: lastPath)
                        }
                    }
                }
            }
        } else {
            // Gallery Tab: Run an automated retry loop that watches for data population
            var attempts = 0
            func simulateGalleryItemClick() {
                let activeStore = galleryManager.activeStore
                if let existing = activeStore.getItemByPath(lastPath) {
                    // Match found! Programmatically trigger the click interaction state
                    activeStore.selectedImageId = existing.id
                    PreviewStore.shared.clearPreview()
                } else if attempts < 15 {
                    // If the gallery files are still loading in the background, retry in 100ms
                    attempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        simulateGalleryItemClick()
                    }
                }
            }
            simulateGalleryItemClick()
        }
    }

    @ViewBuilder
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                tabButton(title: "Browser", tab: 0)

                ForEach(galleryManager.galleries.indices, id: \.self) { i in
                    tabButton(title: galleryManager.galleryName(at: i), tab: i + 1)
                }

                Button(action: { confirmRemoveGallery() }) {    // btn-rmvGll
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle()) // <-- Makes the whole padded area clickable
                }
                .buttonStyle(.plain)
                .padding(4)
                .disabled(!galleryManager.canRemove)

                Button(action: { galleryManager.addGallery() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle()) // <-- Makes the whole padded area clickable
                }
                .buttonStyle(.plain)
                .padding(4)
                .disabled(!galleryManager.canAdd)

                Spacer()
            }
            .padding(.trailing, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
    }

    private func tabButton(title: String, tab: Int) -> some View {
        Button(action: { galleryManager.selectedTab = tab }) {
            Text(title)
                .font(.system(size: 11, weight: galleryManager.selectedTab == tab ? .semibold : .regular))
                .foregroundColor(galleryManager.selectedTab == tab ? .white : .primary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(galleryManager.selectedTab == tab ? Color.accentColor : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .padding(4)
    }

    private func setupTabKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
                return event
            }

            if event.keyCode == 48 { // Tab
                let maxTab = galleryManager.galleries.count
                galleryManager.selectedTab = galleryManager.selectedTab >= maxTab ? 0 : galleryManager.selectedTab + 1
                return nil
            }

            if event.keyCode == 123 { // Left → previous tab
                let maxTab = galleryManager.galleries.count
                galleryManager.selectedTab = galleryManager.selectedTab <= 0 ? maxTab : galleryManager.selectedTab - 1
                return nil
            }

            if event.keyCode == 124 { // Right → next tab
                let maxTab = galleryManager.galleries.count
                galleryManager.selectedTab = galleryManager.selectedTab >= maxTab ? 0 : galleryManager.selectedTab + 1
                return nil
            }

            if galleryManager.selectedTab > 0 {
                if event.keyCode == 126 { // Up
                    navigateToPrevious()
                    return nil
                }
                if event.keyCode == 125 { // Down
                    navigateToNext()
                    return nil
                }
            }

            return event
        }
    }

    private func executeGalleryRemoval() {
        galleryManager.removeLastGallery()
    }

    private func confirmRemoveGallery() {
        guard galleryManager.canRemove, let last = galleryManager.galleries.last else { return }
        if !last.images.isEmpty {
            showDeleteConfirm = true
        } else {
            executeGalleryRemoval()
        }
    }

    @ViewBuilder
    private var arrowKeyButtons: some View {
        HStack(spacing: 0) {
            Button("") { PavePanelController.shared.toggle() }.keyboardShortcut("p", modifiers: []).opacity(0)
            Button("") { AnimationPanelController.shared.toggle() }.keyboardShortcut("a", modifiers: []).opacity(0)
            Button("") { ConvertPanelController().showWindow(nil) }.keyboardShortcut("q", modifiers: []).opacity(0)
            Button("") { settings.fixedSelectionEnabled.toggle() }.keyboardShortcut("f", modifiers: []).opacity(0)
            Button("") { settings.showGrid.toggle() }.keyboardShortcut("g", modifiers: []).opacity(0)
            Button("") { settings.snapToGrid.toggle() }.keyboardShortcut("g", modifiers: [.shift]).opacity(0)
            // Tab switching via Left/Right arrows
            Button("") { 
                let maxTab = galleryManager.galleries.count
                galleryManager.selectedTab = galleryManager.selectedTab <= 0 ? maxTab : galleryManager.selectedTab - 1
            }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { 
                let maxTab = galleryManager.galleries.count
                galleryManager.selectedTab = galleryManager.selectedTab >= maxTab ? 0 : galleryManager.selectedTab + 1
            }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
        }
        .frame(width: 0, height: 0)
    }

    private func navigateToPrevious() {
        guard let current = store.selectedImageId,
              let index = store.images.firstIndex(where: { $0.id == current }), index > 0 else { return }
        store.selectedImageId = store.images[index - 1].id
        PreviewStore.shared.clearPreview()
    }

    private func navigateToNext() {
        guard let current = store.selectedImageId,
              let index = store.images.firstIndex(where: { $0.id == current }), index < store.images.count - 1 else { return }
        store.selectedImageId = store.images[index + 1].id
        PreviewStore.shared.clearPreview()
    }


    @ViewBuilder
    private var toolbarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {       // TBV-HS1
                Toggle("Fixed Size", isOn: $settings.fixedSelectionEnabled)
                    .toggleStyle(.checkbox)
                Text("W:").foregroundColor(.secondary)
                TextField("px", text: $settings.fixedSelectionWidth)
                    .textFieldStyle(.roundedBorder).frame(width: 60).disabled(!settings.fixedSelectionEnabled)
                Text("H:").foregroundColor(.secondary)
                TextField("px", text: $settings.fixedSelectionHeight)
                    .textFieldStyle(.roundedBorder).frame(width: 60).disabled(!settings.fixedSelectionEnabled)

                Divider().frame(height: 16)
                Toggle("Keep Zoom", isOn: $settings.keepZoom).toggleStyle(.checkbox)
                Spacer()
                Button("Clear Gallery") { store.clearAll() }
                Button(action: { ConvertPanelController().showWindow(nil) }) {    // btn-ATA
                    Image(systemName: "film.stack.fill").font(.system(size: 14))
                }
                Button(action: { PavePanelController.shared.toggle() }) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 14))
                }
                Button(action: { AnimationPanelController.shared.toggle() }) {
                    Image(systemName: "play.square.stack")
                        .font(.system(size: 14))
                }
                
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            HStack(spacing: 12) {   // TBV-HS2
                Toggle("Grid", isOn: $settings.showGrid).toggleStyle(.checkbox)
                Text("W:").foregroundColor(.secondary)
                TextField("px", text: $settings.gridWidth).textFieldStyle(.roundedBorder).frame(width: 50)
                Text("H:").foregroundColor(.secondary)
                TextField("px", text: $settings.gridHeight).textFieldStyle(.roundedBorder).frame(width: 50)
                ColorPicker("", selection: Binding(
                    get: { settings.gridColor },
                    set: { settings.gridColorHex = $0.toHex() }
                ))
                .labelsHidden().frame(width: 16, height: 16)
                TextField("px", text: $settings.gridStrokeWidth).textFieldStyle(.roundedBorder).frame(width: 30)

                Divider().frame(height: 16)
                Text("Offset X:").foregroundColor(.secondary).font(.caption)
                Slider(value: $settings.gridOffsetX, in: 0...Double(max(1, settings.parsedGridWidth)), step: 1)
                    .frame(width: 100)
                Text("\(Int(settings.gridOffsetX))").font(.caption).frame(width: 24)
                Text("Y:").foregroundColor(.secondary).font(.caption)
                Slider(value: $settings.gridOffsetY, in: 0...Double(max(1, settings.parsedGridHeight)), step: 1)
                    .frame(width: 100)
                Text("\(Int(settings.gridOffsetY))").font(.caption).frame(width: 24)

                Toggle("Snap", isOn: $settings.snapToGrid).toggleStyle(.checkbox)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 60)).foregroundColor(isTargeted ? .blue : .gray)
                Text("Drop To Add").font(.title2).foregroundColor(isTargeted ? .blue : .secondary)
                Text("or press Cmd+O to load").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5)).padding(20))
            .background(Color(nsColor: .windowBackgroundColor)).contentShape(Rectangle())
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in handleMainDrop(providers: providers) }
            Spacer()
        }
    }

    private func handleMainDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url { Task { await ImageLoader.shared.loadAndSend(url: url, to: store) } }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        Task { @MainActor in store.addImage(image, thumbnail: nil, path: "dropped-\(UUID().uuidString)") }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}