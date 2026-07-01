import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Image Utilities

private let maxImageDimension: CGFloat = 4096
private let thumbnailPixelSize = 100

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

func loadImage(from url: URL) -> NSImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
    
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
       let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
        
        let maxDim = max(width, height)
        if maxDim > maxImageDimension {
            return downsampleImage(at: url, maxPixelSize: Int(maxImageDimension))
        }
    }
    
    return NSImage(contentsOf: url)
}

// MARK: - Error Types & Validations

enum ImageLoadError: LocalizedError {
    case invalidFile(path: String)
    case unsupportedFormat(path: String)
    case fileNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let path): return "Could not load image from \"\(URL(fileURLWithPath: path).lastPathComponent)\". It may be corrupted."
        case .unsupportedFormat(let path): return "Unsupported image format: \"\(URL(fileURLWithPath: path).lastPathComponent)\"."
        case .fileNotFound(let path): return "File not found: \"\(URL(fileURLWithPath: path).lastPathComponent)\"."
        }
    }
}

let supportedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]

func isImageFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    if supportedImageExtensions.contains(ext) { return true }
    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .image) {
        return true
    }
    return false
}

// MARK: - Image Loader

actor ImageLoader {
    static let shared = ImageLoader()
    private init() {}

    func loadAndSend(url: URL, to store: ImageStore) async {
        if url.hasDirectoryPath {
            await loadFolder(url, to: store)
        } else {
            await loadFile(url, to: store)
        }
    }

    private func loadFile(_ url: URL, to store: ImageStore) async {
        guard isImageFile(url) else { return }
        let path = url.path
        let isDup = await MainActor.run { store.isDuplicate(path) }
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
            store.addImage(image, thumbnail: thumbnail, path: path)
        }
    }

    private func loadFolder(_ url: URL, to store: ImageStore) async {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if isImageFile(fileURL) { await loadFile(fileURL, to: store) }
        }
    }

    private nonisolated func setError(_ error: ImageLoadError) async {
        await MainActor.run { ImageStore.shared.lastError = error }
    }
}

// MARK: - Models & Stores

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
}

@MainActor
final class ImageStore: ObservableObject {
    static let shared = ImageStore(loadPersisted: true, persistentName: "g1")
    @Published var images: [ImageItem] = []
    @Published var selectedImageId: UUID?
    @Published var lastError: ImageLoadError?

    private let persistentName: String?
    private let appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ImageViewer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var pathsURL: URL {
        if let name = persistentName {
            appSupportDir.appendingPathComponent("paths-\(name).json")
        } else {
            appSupportDir.appendingPathComponent("paths.json")
        }
    }

    init(persistentName: String?) {
        self.persistentName = persistentName
        loadPaths()
        NotificationCenter.default.addObserver(self, selector: #selector(savePaths), name: NSApplication.willTerminateNotification, object: nil)
    }

    private init(loadPersisted: Bool, persistentName: String?) {
        self.persistentName = persistentName
        if loadPersisted { loadPaths() }
        NotificationCenter.default.addObserver(self, selector: #selector(savePaths), name: NSApplication.willTerminateNotification, object: nil)
    }

    func addImage(_ image: NSImage, thumbnail: NSImage?, path: String) {
        guard !images.contains(where: { $0.filePath == path }) else { return }
        let item = ImageItem(image: image, thumbnail: thumbnail, filePath: path)
        images.append(item)
        if selectedImageId == nil { selectedImageId = item.id }
        savePaths()
    }

    func removeImage(_ id: UUID) {
        images.removeAll { $0.id == id }
        if selectedImageId == id { selectedImageId = images.first?.id }
        if images.isEmpty { NotificationCenter.default.post(name: .clearSelection, object: nil) }
        savePaths()
    }

    func clearAll() {
        images.removeAll()
        selectedImageId = nil
        savePaths()
    }

    func isDuplicate(_ path: String) -> Bool { images.contains(where: { $0.filePath == path }) }
    func getSelectedImage() -> ImageItem? { images.first { $0.id == selectedImageId } }
    func getItemByPath(_ path: String) -> ImageItem? { images.first { $0.filePath == path } }

    @objc private func savePaths() {
        let paths = images.map(\.filePath).filter { !$0.hasPrefix("clipboard") && !$0.hasPrefix("dropped") }
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: pathsURL)
    }

    private func loadPaths() {
        migrateIfNeeded()
        guard let data = try? Data(contentsOf: pathsURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            Task { await ImageLoader.shared.loadAndSend(url: URL(fileURLWithPath: path), to: self) }
        }
    }

    private func migrateIfNeeded() {
        let old = appSupportDir.appendingPathComponent("paths.json")
        guard FileManager.default.fileExists(atPath: old.path) else { return }
        let new = pathsURL
        guard !FileManager.default.fileExists(atPath: new.path) else {
            try? FileManager.default.removeItem(at: old)
            return
        }
        try? FileManager.default.moveItem(at: old, to: new)
    }
}

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard

    @Published var showGrid: Bool { didSet { defaults.set(showGrid, forKey: "showGrid") } }
    @Published var gridWidth: String { didSet { defaults.set(gridWidth, forKey: "gridWidth") } }
    @Published var gridHeight: String { didSet { defaults.set(gridHeight, forKey: "gridHeight") } }
    @Published var fixedSelectionEnabled: Bool { didSet { defaults.set(fixedSelectionEnabled, forKey: "fixedSelectionEnabled") } }
    @Published var fixedSelectionWidth: String { didSet { defaults.set(fixedSelectionWidth, forKey: "fixedSelectionWidth") } }
    @Published var fixedSelectionHeight: String { didSet { defaults.set(fixedSelectionHeight, forKey: "fixedSelectionHeight") } }
    @Published var selectionColorHex: String { didSet { defaults.set(selectionColorHex, forKey: "selectionColorHex") } }
    @Published var keepZoom: Bool { didSet { defaults.set(keepZoom, forKey: "keepZoom") } }
    @Published var snapToGrid: Bool { didSet { defaults.set(snapToGrid, forKey: "snapToGrid") } }
    @Published var gridColorHex: String { didSet { defaults.set(gridColorHex, forKey: "gridColorHex") } }
    @Published var gridStrokeWidth: String { didSet { defaults.set(gridStrokeWidth, forKey: "gridStrokeWidth") } }
    @Published var gridOffsetX: Double { didSet { defaults.set(gridOffsetX, forKey: "gridOffsetX") } }
    @Published var gridOffsetY: Double { didSet { defaults.set(gridOffsetY, forKey: "gridOffsetY") } }

    var selectionColor: Color { Color(hex: selectionColorHex) ?? .blue }
    var gridColor: Color { Color(hex: gridColorHex) ?? .white }
    var parsedGridStrokeWidth: CGFloat { max(0.5, CGFloat(Int(gridStrokeWidth) ?? 1)) }
    var parsedGridWidth: Int { max(1, Int(gridWidth) ?? 50) }
    var parsedGridHeight: Int { max(1, Int(gridHeight) ?? 50) }
    var parsedFixedWidth: Int { max(1, Int(fixedSelectionWidth) ?? 0) }
    var parsedFixedHeight: Int { max(1, Int(fixedSelectionHeight) ?? 0) }

    private init() {
        showGrid = defaults.bool(forKey: "showGrid")
        gridWidth = defaults.string(forKey: "gridWidth") ?? "50"
        gridHeight = defaults.string(forKey: "gridHeight") ?? "50"
        fixedSelectionEnabled = defaults.bool(forKey: "fixedSelectionEnabled")
        fixedSelectionWidth = defaults.string(forKey: "fixedSelectionWidth") ?? ""
        fixedSelectionHeight = defaults.string(forKey: "fixedSelectionHeight") ?? ""
        selectionColorHex = defaults.string(forKey: "selectionColorHex") ?? "#0000FF"
        keepZoom = defaults.bool(forKey: "keepZoom")
        snapToGrid = defaults.bool(forKey: "snapToGrid")
        gridColorHex = defaults.string(forKey: "gridColorHex") ?? "#FFFFFF"
        gridStrokeWidth = defaults.string(forKey: "gridStrokeWidth") ?? "1"
        gridOffsetX = defaults.double(forKey: "gridOffsetX")
        gridOffsetY = defaults.double(forKey: "gridOffsetY")
    }
}

// MARK: - Preview Store

@MainActor
final class PreviewStore: ObservableObject {
    static let shared = PreviewStore()
    @Published var previewItem: ImageItem?

    func setPreview(image: NSImage, path: String) {
        previewItem = ImageItem(image: image, thumbnail: nil, filePath: path)
    }

    func clearPreview() {
        previewItem = nil
    }
}

// MARK: - Pasteboard Utilities

func copyToPasteboard(_ image: NSImage) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setData(pngData, forType: .png)
}

// MARK: - Color Extensions

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    func toHex() -> String {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return "#0000FF" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
