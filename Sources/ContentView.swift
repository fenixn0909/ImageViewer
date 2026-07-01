import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var galleryManager: GalleryManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var previewStore = PreviewStore.shared
    @State private var isTargeted = false
    @State private var errorToShow: ImageLoadError?
    @State private var zoomPercent: Int = 100
    @State private var showDeleteConfirm = false

    private var store: ImageStore { galleryManager.activeStore }
    var displayItem: ImageItem? {
        if galleryManager.selectedTab == 0 {
            previewStore.previewItem
        } else {
            galleryManager.galleries[galleryManager.selectedTab - 1].getSelectedImage()
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
            _ = AnimationPanelController.shared
            setupTabKeyMonitor()
        }
        .onChange(of: galleryManager.selectedTab) { newTab in
            if newTab != 0 { PreviewStore.shared.clearPreview() }
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
            guard event.keyCode == 48 else { return event }
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
                return event
            }
            let maxTab = galleryManager.galleries.count
            galleryManager.selectedTab = galleryManager.selectedTab >= maxTab ? 0 : galleryManager.selectedTab + 1
            return nil
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
            Button("") { navigateToPrevious() }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { navigateToNext() }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { zoomIn() }.keyboardShortcut(.upArrow, modifiers: []).opacity(0)
            Button("") { zoomOut() }.keyboardShortcut(.downArrow, modifiers: []).opacity(0)
            Button("") { AnimationPanelController.shared.toggle() }.keyboardShortcut("a", modifiers: []).opacity(0)
            Button("") { ConvertPanelController().showWindow(nil) }.keyboardShortcut("q", modifiers: []).opacity(0)
        }
        .frame(width: 0, height: 0)
    }

    private func navigateToPrevious() {
        guard let current = store.selectedImageId,
              let index = store.images.firstIndex(where: { $0.id == current }), index > 0 else { return }
        store.selectedImageId = store.images[index - 1].id
    }

    private func navigateToNext() {
        guard let current = store.selectedImageId,
              let index = store.images.firstIndex(where: { $0.id == current }), index < store.images.count - 1 else { return }
        store.selectedImageId = store.images[index + 1].id
    }

    private func zoomIn() {
        NotificationCenter.default.post(name: .zoomIn, object: nil)
    }

    private func zoomOut() {
        NotificationCenter.default.post(name: .zoomOut, object: nil)
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
                Button(action: {    // btn-showAnim
                AnimationPanelController.shared.toggle() }) {
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
