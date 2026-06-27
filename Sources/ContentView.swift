import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Combine

// MARK: - Image Downsampling

private let maxImageDimension: CGFloat = 4096
private let thumbnailPixelSize = 240

func downsampleImage(at url: URL, maxPixelSize: Int) -> NSImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

func downsampleImage(from data: Data, maxPixelSize: Int) -> NSImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

func loadImage(from url: URL) -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    let maxDim = max(image.size.width, image.size.height)
    if maxDim > maxImageDimension {
        return downsampleImage(at: url, maxPixelSize: Int(maxImageDimension))
    }
    return image
}

// MARK: - Image Load Error

enum ImageLoadError: LocalizedError {
    case invalidFile(path: String)
    case unsupportedFormat(path: String)
    case fileNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let path):
            return "Could not load image from \"\(URL(fileURLWithPath: path).lastPathComponent)\". The file may be corrupted or in an unsupported format."
        case .unsupportedFormat(let path):
            return "Unsupported image format: \"\(URL(fileURLWithPath: path).lastPathComponent)\"."
        case .fileNotFound(let path):
            return "File not found: \"\(URL(fileURLWithPath: path).lastPathComponent)\"."
        }
    }
}

let supportedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]

func isImageFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    if supportedImageExtensions.contains(ext) { return true }
    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
       type.conforms(to: .image) {
        return true
    }
    return false
}

// MARK: - Image Loader (async loading with batching)

actor ImageLoader {
    static let shared = ImageLoader()
    private init() {}

    func loadAndSend(url: URL) async {
        if url.hasDirectoryPath {
            await loadFolder(url)
        } else {
            await loadFile(url)
        }
    }

    private func loadFile(_ url: URL) async {
        guard isImageFile(url) else { return }

        let path = url.path
        let isDup = await MainActor.run { ImageStore.shared.isDuplicate(path) }
        guard !isDup else { return }

        guard FileManager.default.fileExists(atPath: path) else {
            await setError(.fileNotFound(path: path))
            return
        }

        guard let image = loadImage(from: url) else {
            await setError(.invalidFile(path: path))
            return
        }

        let thumbnail = downsampleImage(at: url, maxPixelSize: thumbnailPixelSize)

        await MainActor.run {
            ImageStore.shared.addImage(image, thumbnail: thumbnail, path: path)
        }
    }

    private func loadFolder(_ url: URL) async {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentTypeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if isImageFile(fileURL) {
                await loadFile(fileURL)
            }
        }
    }

    private nonisolated func setError(_ error: ImageLoadError) async {
        await MainActor.run {
            ImageStore.shared.lastError = error
        }
    }
}

// MARK: - Event Bus (type-safe replacement for NotificationCenter)

final class EventBus: ObservableObject {
    static let shared = EventBus()

    let imageDropped = PassthroughSubject<(NSImage, String), Never>()
    let pasteImage = PassthroughSubject<NSImage, Never>()
    let clearImage = PassthroughSubject<Void, Never>()
    let copySelection = PassthroughSubject<Void, Never>()
    let fixedSelectionSizeChanged = PassthroughSubject<(Bool, Int, Int), Never>()
    let applyFixedSize = PassthroughSubject<(Int, Int), Never>()
    let allImagesRemoved = PassthroughSubject<Void, Never>()
    let clearSelection = PassthroughSubject<Void, Never>()
    let gridSettingsChanged = PassthroughSubject<(Bool, Int, Int), Never>()

    private init() {}
}

// MARK: - ImageStore

final class ImageStore: ObservableObject {
    nonisolated static let shared = ImageStore()
    @Published var images: [ImageItem] = []
    @Published var selectedImageId: UUID?
    @Published var lastError: ImageLoadError?

    func addImage(_ image: NSImage, thumbnail: NSImage?, path: String) {
        guard !images.contains(where: { $0.filePath == path }) else { return }
        let item = ImageItem(image: image, thumbnail: thumbnail, filePath: path)
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let index = images.firstIndex { candidate in
            let candidateFilename = URL(fileURLWithPath: candidate.filePath).lastPathComponent
            return candidateFilename.localizedStandardCompare(filename) == .orderedDescending
        }
        if let index = index {
            images.insert(item, at: index)
        } else {
            images.append(item)
        }
        if selectedImageId == nil {
            selectedImageId = item.id
        }
    }

    func removeImage(_ id: UUID) {
        images.removeAll { $0.id == id }
        if selectedImageId == id {
            selectedImageId = images.first?.id
        }
        if images.isEmpty {
            EventBus.shared.allImagesRemoved.send()
        }
    }

    func clearAll() {
        images = []
        selectedImageId = nil
    }

    func isDuplicate(_ path: String) -> Bool {
        images.contains(where: { $0.filePath == path })
    }

    func getSelectedImage() -> ImageItem? {
        guard let id = selectedImageId else { return nil }
        return images.first { $0.id == id }
    }
}

// MARK: - SettingsManager

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    @Published var showGrid: Bool {
        didSet { defaults.set(showGrid, forKey: "showGrid") }
    }

    @Published var gridWidth: String {
        didSet { defaults.set(gridWidth, forKey: "gridWidth") }
    }

    @Published var gridHeight: String {
        didSet { defaults.set(gridHeight, forKey: "gridHeight") }
    }

    @Published var fixedSelectionEnabled: Bool {
        didSet { defaults.set(fixedSelectionEnabled, forKey: "fixedSelectionEnabled") }
    }

    @Published var fixedSelectionWidth: String {
        didSet { defaults.set(fixedSelectionWidth, forKey: "fixedSelectionWidth") }
    }

    @Published var fixedSelectionHeight: String {
        didSet { defaults.set(fixedSelectionHeight, forKey: "fixedSelectionHeight") }
    }

    @Published var selectionColorHex: String {
        didSet { defaults.set(selectionColorHex, forKey: "selectionColorHex") }
    }

    @Published var keepZoom: Bool {
        didSet { defaults.set(keepZoom, forKey: "keepZoom") }
    }

    var selectionColor: Color {
        Color(hex: selectionColorHex) ?? .blue
    }

    var parsedGridWidth: Int {
        max(1, Int(gridWidth) ?? 50)
    }

    var parsedGridHeight: Int {
        max(1, Int(gridHeight) ?? 50)
    }

    var parsedFixedWidth: Int {
        max(1, Int(fixedSelectionWidth) ?? 0)
    }

    var parsedFixedHeight: Int {
        max(1, Int(fixedSelectionHeight) ?? 0)
    }

    private init() {
        showGrid = defaults.bool(forKey: "showGrid")
        gridWidth = defaults.string(forKey: "gridWidth") ?? "50"
        gridHeight = defaults.string(forKey: "gridHeight") ?? "50"
        fixedSelectionEnabled = defaults.bool(forKey: "fixedSelectionEnabled")
        fixedSelectionWidth = defaults.string(forKey: "fixedSelectionWidth") ?? ""
        fixedSelectionHeight = defaults.string(forKey: "fixedSelectionHeight") ?? ""
        selectionColorHex = defaults.string(forKey: "selectionColorHex") ?? "#0000FF"
        keepZoom = defaults.bool(forKey: "keepZoom")
    }
}

// MARK: - Color Extensions

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return "#0000FF" }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - ImageItem

struct ImageItem: Identifiable, Equatable {
    let id: UUID
    let image: NSImage
    let thumbnail: NSImage?
    let filePath: String

    init(image: NSImage, thumbnail: NSImage? = nil, filePath: String) {
        self.id = UUID()
        self.image = image
        self.thumbnail = thumbnail
        self.filePath = filePath
    }

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var store = ImageStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isTargeted = false
    @State private var errorToShow: ImageLoadError?
    @State private var zoomPercent: Int = 100

    var selectedImage: ImageItem? {
        store.getSelectedImage()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarView

            HSplitView {
                GallerySidebar(store: store, isTargeted: $isTargeted)
                    .frame(minWidth: 120, maxWidth: 200)

                ZStack {
                    if let item = selectedImage {
                        ImagePreview(item: item, onZoomChange: { zoomPercent = $0 })
                    } else {
                        emptyStateView
                    }
                }
                .frame(minWidth: 400, minHeight: 300)
            }
            .frame(maxHeight: .infinity)

            FileInfoBar(item: selectedImage, zoomPercent: selectedImage != nil ? zoomPercent : nil)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(EventBus.shared.clearImage) { _ in
            store.clearAll()
        }
        .onReceive(EventBus.shared.imageDropped) { (image, path) in
            store.addImage(image, thumbnail: nil, path: path)
        }
        .onReceive(EventBus.shared.pasteImage) { image in
            let path = "clipboard-\(UUID().uuidString)"
            store.addImage(image, thumbnail: nil, path: path)
        }
        .onReceive(EventBus.shared.allImagesRemoved) { _ in
            EventBus.shared.clearSelection.send()
        }
        .onReceive(store.$lastError) { error in
            errorToShow = error
        }
        .alert("Error", isPresented: .init(
            get: { errorToShow != nil },
            set: { if !$0 { errorToShow = nil } }
        )) {
            Text(errorToShow?.localizedDescription ?? "Unknown error")
        }
        .background(arrowKeyButtons)
    }

    @ViewBuilder
    private var arrowKeyButtons: some View {
        HStack(spacing: 0) {
            Button("") {
                navigateToPrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button("") {
                navigateToNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .frame(width: 0, height: 0)
    }

    private func navigateToPrevious() {
        guard let current = store.selectedImageId,
              let index = store.images.firstIndex(where: { $0.id == current }),
              index > 0 else { return }
        store.selectedImageId = store.images[index - 1].id
    }

    private func navigateToNext() {
        guard let current = store.selectedImageId,
              let index = store.images.firstIndex(where: { $0.id == current }),
              index < store.images.count - 1 else { return }
        store.selectedImageId = store.images[index + 1].id
    }

    @ViewBuilder
    private var toolbarView: some View {
        HStack(spacing: 12) {
            Toggle("Fixed Size", isOn: $settings.fixedSelectionEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: settings.fixedSelectionEnabled) { _ in
                    notifyFixedSizeChange()
                }

            Text("W:")
                .foregroundColor(.secondary)

            TextField("px", text: $settings.fixedSelectionWidth)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .disabled(!settings.fixedSelectionEnabled)
                .onChange(of: settings.fixedSelectionWidth) { _ in
                    notifyFixedSizeChange()
                }

            Text("H:")
                .foregroundColor(.secondary)

            TextField("px", text: $settings.fixedSelectionHeight)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .disabled(!settings.fixedSelectionEnabled)
                .onChange(of: settings.fixedSelectionHeight) { _ in
                    notifyFixedSizeChange()
                }

            Button("Apply") {
                applyFixedSize()
            }
            .disabled(!settings.fixedSelectionEnabled || Int(settings.fixedSelectionWidth) ?? 0 <= 0 || Int(settings.fixedSelectionHeight) ?? 0 <= 0)

            Divider().frame(height: 16)

            Toggle("Grid", isOn: $settings.showGrid)
                .toggleStyle(.checkbox)
                .onChange(of: settings.showGrid) { _ in
                    notifyGridChange()
                }

            Text("W:")
                .foregroundColor(.secondary)

            TextField("px", text: $settings.gridWidth)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .onChange(of: settings.gridWidth) { _ in
                    notifyGridChange()
                }

            Text("H:")
                .foregroundColor(.secondary)

            TextField("px", text: $settings.gridHeight)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .onChange(of: settings.gridHeight) { _ in
                    notifyGridChange()
                }

            Divider().frame(height: 16)

            Toggle("Keep Zoom", isOn: $settings.keepZoom)
                .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(isTargeted ? .blue : .gray)

                Text("Drop To Add")
                    .font(.title2)
                    .foregroundColor(isTargeted ? .blue : .secondary)

                Text("or press Cmd+O to load")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5))
                    .padding(20)
            )
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .image, .png, .tiff], isTargeted: $isTargeted) { providers in
                handleMainDrop(providers: providers)
            }

            Spacer()
        }
    }

    private func notifyFixedSizeChange() {
        EventBus.shared.fixedSelectionSizeChanged.send(
            (settings.fixedSelectionEnabled, settings.parsedFixedWidth, settings.parsedFixedHeight)
        )
    }

    private func applyFixedSize() {
        let w = settings.parsedFixedWidth
        let h = settings.parsedFixedHeight
        guard w > 0, h > 0 else { return }
        EventBus.shared.applyFixedSize.send((w, h))
    }

    private func notifyGridChange() {
        EventBus.shared.gridSettingsChanged.send(
            (settings.showGrid, settings.parsedGridWidth, settings.parsedGridHeight)
        )
    }

    private func handleMainDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { await ImageLoader.shared.loadAndSend(url: url) }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    let tempPath = "dropped-\(UUID().uuidString)"
                    Task { @MainActor in
                        EventBus.shared.imageDropped.send((image, tempPath))
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - FileInfoBar

struct FileInfoBar: View {
    let item: ImageItem?
    let zoomPercent: Int?

    var fileSize: String {
        guard let item = item else { return "" }
        let path = item.filePath
        if path.hasPrefix("clipboard") || path.hasPrefix("dropped") || path.hasPrefix("paste") {
            if let tiffData = item.image.tiffRepresentation {
                return formatBytes(tiffData.count)
            }
            return "Unknown"
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }
        return formatBytes(Int(size))
    }

    var fileName: String {
        guard let item = item else { return "" }
        if item.filePath.hasPrefix("clipboard") || item.filePath.hasPrefix("dropped") {
            return "(Clipboard/Pasted)"
        }
        return URL(fileURLWithPath: item.filePath).lastPathComponent
    }

    var imageDimensions: String {
        guard let item = item else { return "" }
        let size = item.image.size
        return "\(Int(size.width)) \u{00D7} \(Int(size.height)) px"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    var body: some View {
        HStack {
            if let item = item {
                Text(fileName)
                    .font(.system(size: 11))

                Divider().frame(height: 12)

                Text(imageDimensions)
                    .font(.system(size: 11))

                Divider().frame(height: 12)

                Text(fileSize)
                    .font(.system(size: 11))

                if !item.filePath.hasPrefix("clipboard") && !item.filePath.hasPrefix("dropped") {
                    Divider().frame(height: 12)

                    Text(item.filePath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let zoomPercent = zoomPercent {
                    Divider().frame(height: 12)

                    Text("\(zoomPercent)%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .top
        )
    }
}

// MARK: - GallerySidebar

struct GallerySidebar: View {
    @ObservedObject var store: ImageStore
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.images.isEmpty ? "Gallery" : "Images (\(store.images.count))")
                    .font(.headline)
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            if store.images.isEmpty {
                VStack {
                    Spacer()
                    Text("No images")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(store.images) { item in
                            ThumbnailView(
                                image: item.thumbnail ?? item.image,
                                isSelected: store.selectedImageId == item.id,
                                onRemove: {
                                    store.removeImage(item.id)
                                }
                            )
                            .onTapGesture {
                                store.selectedImageId = item.id
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: .infinity)
            }

            DropAddButton(store: store, isTargeted: $isTargeted)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - DropAddButton

struct DropAddButton: View {
    @ObservedObject var store: ImageStore
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(isTargeted ? .blue : .gray)

            Text("Add")
                .font(.caption2)
                .foregroundColor(isTargeted ? .blue : .secondary)
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5))
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
        )
        .padding(8)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image, .png, .tiff], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { await ImageLoader.shared.loadAndSend(url: url) }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    let tempPath = "dropped-\(UUID().uuidString)"
                    Task { @MainActor in
                        EventBus.shared.imageDropped.send((image, tempPath))
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - ThumbnailView

struct ThumbnailView: View {
    let image: NSImage
    let isSelected: Bool
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipped()
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.red).frame(width: 14, height: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - ImagePreview

struct ImagePreview: View {
    let item: ImageItem
    let onZoomChange: (Int) -> Void
    @ObservedObject private var settings = SettingsManager.shared
    @State private var fixedWidth: Int?
    @State private var fixedHeight: Int?
    @State private var selectionRect: CGRect?
    @State private var isSelecting = false
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var resizeEdge: ResizeEdge = .none
    @State private var startPoint: CGPoint = .zero
    @State private var dragStartRect: CGRect = .zero
    @State private var dragStartPoint: CGPoint = .zero
    @State private var fitScale: CGFloat = 1.0
    @State private var zoomLevel: CGFloat = 1.0
    @State private var lastZoomLevel: CGFloat = 1.0
    @State private var showGrid: Bool = false
    @State private var gridWidth: Int = 50
    @State private var gridHeight: Int = 50

    private var displayScale: CGFloat {
        fitScale * zoomLevel
    }

    enum ResizeEdge {
        case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: item.image.size.width * displayScale,
                            height: item.image.size.height * displayScale
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    handleImageDrag(value: value)
                                }
                                .onEnded { _ in
                                    isSelecting = false
                                    isDragging = false
                                    isResizing = false
                                    resizeEdge = .none
                                }
                        )

                    if showGrid {
                        GridView(
                            gridWidth: gridWidth,
                            gridHeight: gridHeight,
                            imageWidth: item.image.size.width,
                            imageHeight: item.image.size.height,
                            currentScale: displayScale
                        )
                    }

                    if let rect = selectionRect, rect.width > 5 && rect.height > 5 {
                        let scaledRect = CGRect(
                            x: rect.origin.x * displayScale,
                            y: rect.origin.y * displayScale,
                            width: rect.width * displayScale,
                            height: rect.height * displayScale
                        )

                        SelectionOverlay(
                            rect: scaledRect,
                            pixelWidth: Int(rect.width),
                            pixelHeight: Int(rect.height),
                            selectionColor: settings.selectionColor,
                            isFixedSize: fixedWidth != nil && fixedHeight != nil,
                            onCopy: copySelection,
                            onClear: { selectionRect = nil },
                            onColorChange: { newColor in
                                settings.selectionColorHex = newColor.toHex()
                            }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleSelectionDrag(value: value, rect: scaledRect)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    isResizing = false
                                    resizeEdge = .none
                                }
                        )
                    }
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                .contentShape(Rectangle())
                .onAppear {
                    updateImageFrame(imageSize: item.image.size, viewSize: geometry.size)
                }
                .onChange(of: geometry.size) { newSize in
                    updateImageFrame(imageSize: item.image.size, viewSize: newSize)
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomLevel = max(0.1, min(50, lastZoomLevel * value))
                        }
                        .onEnded { _ in
                            lastZoomLevel = zoomLevel
                        }
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: item.id) { _ in
            selectionRect = nil
            if !settings.keepZoom {
                zoomLevel = 1.0
                lastZoomLevel = 1.0
            }
        }
        .onChange(of: displayScale) { _ in
            onZoomChange(Int((displayScale * 100).rounded()))
        }
        .onReceive(EventBus.shared.copySelection) { _ in
            copySelection()
        }
        .onReceive(EventBus.shared.fixedSelectionSizeChanged) { (enabled, w, h) in
            fixedWidth = enabled ? w : nil
            fixedHeight = enabled ? h : nil
        }
        .onReceive(EventBus.shared.applyFixedSize) { (fw, fh) in
            guard fw > 0, fh > 0 else { return }
            let clampedWidth = min(CGFloat(fw), item.image.size.width)
            let clampedHeight = min(CGFloat(fh), item.image.size.height)
            let x = (item.image.size.width - clampedWidth) / 2
            let y = (item.image.size.height - clampedHeight) / 2
            selectionRect = CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
        }
        .onReceive(EventBus.shared.clearSelection) { _ in
            selectionRect = nil
        }
        .onReceive(EventBus.shared.gridSettingsChanged) { (show, w, h) in
            showGrid = show
            gridWidth = w
            gridHeight = h
        }
    }

    struct GridView: View {
        let gridWidth: Int
        let gridHeight: Int
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        let currentScale: CGFloat

        var body: some View {
            let gw = max(1, gridWidth)
            let gh = max(1, gridHeight)

            Canvas { context, size in
                let scaledGridWidth = CGFloat(gw) * currentScale
                let scaledGridHeight = CGFloat(gh) * currentScale
                let lineColor = Color.white.opacity(0.5)

                var x: CGFloat = 0
                while x <= size.width {
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        },
                        with: .color(lineColor),
                        lineWidth: 1
                    )
                    x += scaledGridWidth
                }

                var y: CGFloat = 0
                while y <= size.height {
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        },
                        with: .color(lineColor),
                        lineWidth: 1
                    )
                    y += scaledGridHeight
                }
            }
            .frame(width: imageWidth * currentScale, height: imageHeight * currentScale)
        }
    }

    private func handleImageDrag(value: DragGesture.Value) {
        let currentPoint = CGPoint(
            x: value.location.x / displayScale,
            y: value.location.y / displayScale
        )

        if !isSelecting {
            isSelecting = true
            startPoint = CGPoint(
                x: max(0, min(currentPoint.x, item.image.size.width)),
                y: max(0, min(currentPoint.y, item.image.size.height))
            )

            if let fw = fixedWidth, let fh = fixedHeight, fw > 0, fh > 0 {
                let clampedWidth = min(CGFloat(fw), item.image.size.width)
                let clampedHeight = min(CGFloat(fh), item.image.size.height)
                let x = max(0, min(startPoint.x, item.image.size.width - clampedWidth))
                let y = max(0, min(startPoint.y, item.image.size.height - clampedHeight))
                selectionRect = CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
            } else {
                selectionRect = CGRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1)
            }
        } else {
            if let fw = fixedWidth, let fh = fixedHeight, fw > 0, fh > 0 {
                let clampedWidth = min(CGFloat(fw), item.image.size.width)
                let clampedHeight = min(CGFloat(fh), item.image.size.height)
                let x = max(0, min(currentPoint.x - clampedWidth / 2, item.image.size.width - clampedWidth))
                let y = max(0, min(currentPoint.y - clampedHeight / 2, item.image.size.height - clampedHeight))
                selectionRect = CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
            } else {
                let x = max(0, min(startPoint.x, currentPoint.x))
                let y = max(0, min(startPoint.y, currentPoint.y))
                let width = max(1, min(abs(currentPoint.x - startPoint.x), item.image.size.width - x))
                let height = max(1, min(abs(currentPoint.y - startPoint.y), item.image.size.height - y))
                selectionRect = CGRect(x: x, y: y, width: width, height: height)
            }
        }
    }

    private func handleSelectionDrag(value: DragGesture.Value, rect: CGRect) {
        guard let selRect = selectionRect else { return }

        let currentPoint = CGPoint(
            x: value.location.x / displayScale,
            y: value.location.y / displayScale
        )

        let isFixedSize = fixedWidth != nil && fixedHeight != nil

        if !isFixedSize && !isDragging && !isResizing {
            if isNearEdge(value.location, rect: rect, tolerance: 12) {
                isResizing = true
                resizeEdge = getEdge(value.location, rect: rect, tolerance: 12)
                dragStartRect = selRect
                dragStartPoint = currentPoint
                return
            }
        }

        if !isFixedSize && isResizing {
            let delta = CGPoint(
                x: currentPoint.x - dragStartPoint.x,
                y: currentPoint.y - dragStartPoint.y
            )
            selectionRect = applyResizeToRect(dragStartRect, delta: delta, edge: resizeEdge)
        } else {
            if !isDragging {
                isDragging = true
                dragStartRect = selRect
                dragStartPoint = currentPoint
            }
            let delta = CGPoint(
                x: currentPoint.x - dragStartPoint.x,
                y: currentPoint.y - dragStartPoint.y
            )
            let newOrigin = CGPoint(
                x: dragStartRect.origin.x + delta.x,
                y: dragStartRect.origin.y + delta.y
            )
            let clampedX = max(0, min(newOrigin.x, item.image.size.width - dragStartRect.width))
            let clampedY = max(0, min(newOrigin.y, item.image.size.height - dragStartRect.height))
            selectionRect = CGRect(x: clampedX, y: clampedY, width: dragStartRect.width, height: dragStartRect.height)
        }
    }

    struct SelectionOverlay: View {
        let rect: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
        let selectionColor: Color
        let isFixedSize: Bool
        let onCopy: () -> Void
        let onClear: () -> Void
        let onColorChange: (Color) -> Void

        @State private var dashOffset: CGFloat = 0
        @State private var showColorPicker = false

        let presetColors: [Color] = [
            .blue, .red, .green, .yellow, .orange, .purple, .pink, .cyan, .mint, .indigo
        ]

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(selectionColor.opacity(0.2))

                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4], dashPhase: dashOffset))
                    .foregroundColor(selectionColor)

                if !isFixedSize {
                    selectionHandles
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")

                    Button(action: { showColorPicker.toggle() }) {
                        Circle()
                            .fill(selectionColor)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Change color")
                    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                        ColorPickerPanel(
                            selectionColor: selectionColor,
                            onColorChange: { newColor in
                                onColorChange(newColor)
                                showColorPicker = false
                            },
                            onClose: { showColorPicker = false }
                        )
                    }

                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Clear selection")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectionColor)
                .foregroundColor(.white)
                .cornerRadius(4)
                .offset(y: 28)
                .fixedSize()
            }
            .overlay(alignment: .bottom) {
                Text("\(pixelWidth) \u{00D7} \(pixelHeight) px")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectionColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .offset(y: 58)
                    .fixedSize()
                    .allowsHitTesting(false)
            }
            .task {
                await animateDash()
            }
            .onDisappear {
                NSColorPanel.shared.close()
            }
        }

        @ViewBuilder
        private var selectionHandles: some View {
            let h = rect.height
            let w = rect.width
            let s: CGFloat = 12

            Group {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: 0, y: h / 2)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: w, y: h / 2)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: w / 2, y: 0)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: w / 2, y: h)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: 0, y: 0)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: w, y: 0)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: 0, y: h)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .overlay(Rectangle().stroke(selectionColor, lineWidth: 1))
                    .position(x: w, y: h)
            }
        }

        @MainActor
        private func animateDash() async {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                dashOffset -= 1
                if dashOffset < -20 { dashOffset = 0 }
            }
        }
    }

    struct ColorPickerPanel: View {
        let selectionColor: Color
        let onColorChange: (Color) -> Void
        let onClose: () -> Void

        let presetColors: [Color] = [
            .blue, .red, .green, .yellow, .orange, .purple, .pink, .cyan, .mint, .indigo
        ]

        private let circleSize: CGFloat = 24
        private let circleSpacing: CGFloat = 5

        private var calculatedWidth: CGFloat {
            let buttonPadding: CGFloat = 16
            let sidePadding: CGFloat = 16
            return buttonPadding + (CGFloat(presetColors.count) * circleSize) + (CGFloat(presetColors.count - 1) * circleSpacing) + sidePadding
        }

        var body: some View {
            VStack(spacing: 8) {
                Button(action: toggleColorPanel) {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 12))
                        Text("Wheel")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                HStack(spacing: circleSpacing) {
                    ForEach(presetColors, id: \.self) { color in
                        Button(action: {
                            onColorChange(color)
                            onClose()
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: circleSize, height: circleSize)
                                .overlay(
                                    Circle()
                                        .stroke(selectionColor == color ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }
                }
            }
            .padding(8)
            .frame(width: calculatedWidth)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
            .shadow(radius: 5)
            .allowsHitTesting(true)
            .onDisappear {
                NSColorPanel.shared.close()
            }
        }

        private func toggleColorPanel() {
            let panel = NSColorPanel.shared
            if panel.isVisible {
                panel.close()
            } else {
                panel.color = NSColor(selectionColor)
                panel.showsAlpha = true
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func applyResizeToRect(_ rect: CGRect, delta: CGPoint, edge: ResizeEdge) -> CGRect {
        var newRect = rect

        switch edge {
        case .left:
            let newX = max(0, rect.origin.x + delta.x)
            let newWidth = rect.width - delta.x
            if newWidth > 10 && newX >= 0 {
                newRect = CGRect(x: newX, y: rect.origin.y, width: newWidth, height: rect.height)
            }
        case .right:
            let newWidth = max(10, min(rect.width + delta.x, item.image.size.width - rect.origin.x))
            newRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: newWidth, height: rect.height)
        case .top:
            let newY = max(0, rect.origin.y + delta.y)
            let newHeight = rect.height - delta.y
            if newHeight > 10 && newY >= 0 {
                newRect = CGRect(x: rect.origin.x, y: newY, width: rect.width, height: newHeight)
            }
        case .bottom:
            let newHeight = max(10, min(rect.height + delta.y, item.image.size.height - rect.origin.y))
            newRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: newHeight)
        case .topLeft:
            let newX = max(0, rect.origin.x + delta.x)
            let newY = max(0, rect.origin.y + delta.y)
            let newWidth = rect.width - delta.x
            let newHeight = rect.height - delta.y
            if newWidth > 10 && newHeight > 10 && newX >= 0 && newY >= 0 {
                newRect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
            }
        case .topRight:
            let newY = max(0, rect.origin.y + delta.y)
            let newWidth = max(10, min(rect.width + delta.x, item.image.size.width - rect.origin.x))
            let newHeight = rect.height - delta.y
            if newWidth > 10 && newHeight > 10 && newY >= 0 {
                newRect = CGRect(x: rect.origin.x, y: newY, width: newWidth, height: newHeight)
            }
        case .bottomLeft:
            let newX = max(0, rect.origin.x + delta.x)
            let newWidth = rect.width - delta.x
            let newHeight = max(10, min(rect.height + delta.y, item.image.size.height - rect.origin.y))
            if newWidth > 10 && newHeight > 10 && newX >= 0 {
                newRect = CGRect(x: newX, y: rect.origin.y, width: newWidth, height: newHeight)
            }
        case .bottomRight:
            let newWidth = max(10, min(rect.width + delta.x, item.image.size.width - rect.origin.x))
            let newHeight = max(10, min(rect.height + delta.y, item.image.size.height - rect.origin.y))
            newRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: newWidth, height: newHeight)
        case .none:
            break
        }

        return newRect
    }

    private func isNearEdge(_ point: CGPoint, rect: CGRect, tolerance: CGFloat) -> Bool {
        let nearLeft = abs(point.x - rect.minX) < tolerance
        let nearRight = abs(point.x - rect.maxX) < tolerance
        let nearTop = abs(point.y - rect.minY) < tolerance
        let nearBottom = abs(point.y - rect.maxY) < tolerance
        return nearLeft || nearRight || nearTop || nearBottom
    }

    private func getEdge(_ point: CGPoint, rect: CGRect, tolerance: CGFloat) -> ResizeEdge {
        let nearLeft = abs(point.x - rect.minX) < tolerance
        let nearRight = abs(point.x - rect.maxX) < tolerance
        let nearTop = abs(point.y - rect.minY) < tolerance
        let nearBottom = abs(point.y - rect.maxY) < tolerance

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearRight && nearBottom { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return .none
    }

    private func copySelection() {
        guard let rect = selectionRect else { return }

        guard let cgImage = item.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let scaleX = CGFloat(cgImage.width) / item.image.size.width
        let scaleY = CGFloat(cgImage.height) / item.image.size.height

        let cropX = Int(rect.origin.x * scaleX)
        let cropY = Int(rect.origin.y * scaleY)
        let cropWidth = Int(rect.width * scaleX)
        let cropHeight = Int(rect.height * scaleY)

        guard cropWidth > 0, cropHeight > 0 else { return }
        guard cropX >= 0, cropY >= 0 else { return }
        guard cropX + cropWidth <= cgImage.width else { return }
        guard cropY + cropHeight <= cgImage.height else { return }

        let pixelRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else { return }

        let targetWidth = Int(rect.width)
        let targetHeight = Int(rect.height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        context.interpolationQuality = .high
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let finalCGImage = context.makeImage() else { return }

        let finalImage = NSImage(cgImage: finalCGImage, size: NSSize(width: targetWidth, height: targetHeight))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }

    private func updateImageFrame(imageSize: CGSize, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return }

        let aspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height

        if aspectRatio > viewAspectRatio {
            fitScale = viewSize.width / imageSize.width
        } else {
            fitScale = viewSize.height / imageSize.height
        }
    }
}
