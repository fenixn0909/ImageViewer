import AppKit
import SwiftUI

final class PavePanelController: NSWindowController {
    static let shared = PavePanelController()
    private var monitor: Any?

    private init() {
        let savedFrame = Self.loadFrame()
        let win = NSWindow(
            contentRect: savedFrame ?? NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Pave"
        win.level = .normal
        win.hidesOnDeactivate = false
        win.minSize = NSSize(width: 350, height: 250)
        let hostingView = NSHostingView(rootView: PaveContentView())
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView
        super.init(window: win)
        if let frame = savedFrame { win.setFrame(frame, display: false) }
        NotificationCenter.default.addObserver(self, selector: #selector(saveState), name: NSApplication.willTerminateNotification, object: nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isVisible == true, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 35 {
                self.window?.close()
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }

    @objc private func saveState() {
        guard let win = window else { return }
        UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: "paveWindowFrame")
    }

    private static func loadFrame() -> NSRect? {
        guard let str = UserDefaults.standard.string(forKey: "paveWindowFrame") else { return nil }
        let rect = NSRectFromString(str)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    func toggle() {
        if isWindowLoaded, window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            positionToRightOfMainWindow()
            window?.makeKeyAndOrderFront(nil)
        }
    }

    private func positionToRightOfMainWindow() {
        guard let mainWindow = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first,
              let panel = window else { return }
        let mainFrame = mainWindow.frame
        panel.setFrameOrigin(NSPoint(
            x: mainFrame.maxX + 10,
            y: mainFrame.midY - panel.frame.height / 2
        ))
    }
}

// MARK: - Checker Color

private final class CheckerColorHandler: NSObject {
    static let shared = CheckerColorHandler()
    @objc func colorChanged(_ sender: NSColorPanel) {
        let color = sender.color
        if let srgb = color.usingColorSpace(.sRGB) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
            UserDefaults.standard.set(hex, forKey: "checkerColor")
        }
    }
}

// MARK: - Layer & Board Models

struct BoardLayer: Identifiable {
    var id = UUID()
    var name: String
    var canvasImage: NSImage?
    var isVisible = true
}

struct BoardData {
    var canvasWidth: CGFloat = 1024
    var canvasHeight: CGFloat = 1024
    var bgColor: Color = .white
    var layers: [BoardLayer] = [BoardLayer(name: "Layer 1")]
    var selectedLayerId: UUID?
    var undoStack: [[BoardLayer]] = []
    var redoStack: [[BoardLayer]] = []

    var floatingImage: NSImage?
    var floatingOrigin: CGPoint = .zero
    var dragOffset: CGSize = .zero
    var showFloating = false

    var showGrid = false
    var gridWidth: CGFloat = 32
    var gridHeight: CGFloat = 32
    var gridStrokeColor: Color = .gray.opacity(0.4)
    var gridStrokeWidth: CGFloat = 0.5
    var snapToGrid = false

    var selectionRect: CGRect?
    var selectionStart: CGPoint = .zero
    var isSelecting = false

    var selectedLayerIndex: Int? {
        guard let id = selectedLayerId else { return nil }
        return layers.firstIndex(where: { $0.id == id })
    }
}

// MARK: - Persistence

private var paveAppSupportDir: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("ImageViewer").appendingPathComponent("Pave")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

private func boardDir(_ index: Int) -> URL {
    paveAppSupportDir.appendingPathComponent("board_\(index)")
}

private func metadataURL(_ index: Int) -> URL {
    boardDir(index).appendingPathComponent("metadata.json")
}

private func layerImageURL(boardIndex: Int, layerId: String) -> URL {
    boardDir(boardIndex).appendingPathComponent("layer_\(layerId).png")
}

private struct LayerMeta: Codable {
    let id: String
    let name: String
    let isVisible: Bool
    let hasImage: Bool
}

private struct BoardMeta: Codable {
    let canvasWidth: Double
    let canvasHeight: Double
    let bgColorHex: String
    let showGrid: Bool
    let gridWidth: Double
    let gridHeight: Double
    let gridStrokeColorHex: String
    let gridStrokeWidth: Double
    let snapToGrid: Bool
    let layers: [LayerMeta]
    let selectedLayerId: String?

    init(canvasWidth: Double, canvasHeight: Double, bgColorHex: String, showGrid: Bool,
         gridWidth: Double, gridHeight: Double, gridStrokeColorHex: String, gridStrokeWidth: Double,
         snapToGrid: Bool, layers: [LayerMeta], selectedLayerId: String?) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.bgColorHex = bgColorHex
        self.showGrid = showGrid
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.gridStrokeColorHex = gridStrokeColorHex
        self.gridStrokeWidth = gridStrokeWidth
        self.snapToGrid = snapToGrid
        self.layers = layers
        self.selectedLayerId = selectedLayerId
    }

    // Custom decoding so boards saved before grid-stroke/snap were added still load fine.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canvasWidth = try c.decode(Double.self, forKey: .canvasWidth)
        canvasHeight = try c.decode(Double.self, forKey: .canvasHeight)
        bgColorHex = try c.decode(String.self, forKey: .bgColorHex)
        showGrid = try c.decode(Bool.self, forKey: .showGrid)
        gridWidth = try c.decode(Double.self, forKey: .gridWidth)
        gridHeight = try c.decode(Double.self, forKey: .gridHeight)
        gridStrokeColorHex = try c.decodeIfPresent(String.self, forKey: .gridStrokeColorHex) ?? "#8080807F"
        gridStrokeWidth = try c.decodeIfPresent(Double.self, forKey: .gridStrokeWidth) ?? 0.5
        snapToGrid = try c.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? false
        layers = try c.decode([LayerMeta].self, forKey: .layers)
        selectedLayerId = try c.decodeIfPresent(String.self, forKey: .selectedLayerId)
    }
}

func savePaveBoards(_ boards: [BoardData]) {
    try? FileManager.default.createDirectory(at: paveAppSupportDir, withIntermediateDirectories: true)
    let existing = (try? FileManager.default.contentsOfDirectory(at: paveAppSupportDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    for item in existing {
        try? FileManager.default.removeItem(at: item)
    }
    for (i, board) in boards.enumerated() {
        let dir = boardDir(i)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var layersMeta: [LayerMeta] = []
        for layer in board.layers {
            let lid = layer.id.uuidString
            layersMeta.append(LayerMeta(id: lid, name: layer.name, isVisible: layer.isVisible, hasImage: layer.canvasImage != nil))
            if let img = layer.canvasImage, let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: layerImageURL(boardIndex: i, layerId: lid))
            }
        }
        let meta = BoardMeta(
            canvasWidth: board.canvasWidth, canvasHeight: board.canvasHeight,
            bgColorHex: board.bgColor.toHex(),
            showGrid: board.showGrid, gridWidth: board.gridWidth, gridHeight: board.gridHeight,
            gridStrokeColorHex: board.gridStrokeColor.toHexWithAlpha(), gridStrokeWidth: board.gridStrokeWidth,
            snapToGrid: board.snapToGrid,
            layers: layersMeta, selectedLayerId: board.selectedLayerId?.uuidString
        )
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metadataURL(i))
        }
    }
}

func loadPaveBoards() -> [BoardData] {
    guard let entries = try? FileManager.default.contentsOfDirectory(at: paveAppSupportDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [BoardData()] }
    let dirs = entries.filter { $0.lastPathComponent.hasPrefix("board_") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !dirs.isEmpty else { return [BoardData()] }
    var boards: [BoardData] = []
    for dir in dirs {
        guard let index = Int(dir.lastPathComponent.dropFirst(6)),
              let data = try? Data(contentsOf: metadataURL(index)),
              let meta = try? JSONDecoder().decode(BoardMeta.self, from: data) else { continue }
        var layers: [BoardLayer] = []
        for lm in meta.layers {
            let img: NSImage? = lm.hasImage ? NSImage(contentsOf: layerImageURL(boardIndex: index, layerId: lm.id)) : nil
            var layer = BoardLayer(name: lm.name, canvasImage: img, isVisible: lm.isVisible)
            layer.id = UUID(uuidString: lm.id) ?? layer.id
            layers.append(layer)
        }
        let selId = meta.selectedLayerId.flatMap { UUID(uuidString: $0) }
        boards.append(BoardData(
            canvasWidth: CGFloat(meta.canvasWidth), canvasHeight: CGFloat(meta.canvasHeight),
            bgColor: Color(hex: meta.bgColorHex) ?? .white,
            layers: layers, selectedLayerId: selId,
            showGrid: meta.showGrid, gridWidth: CGFloat(meta.gridWidth), gridHeight: CGFloat(meta.gridHeight),
            gridStrokeColor: Color(hex: meta.gridStrokeColorHex) ?? .gray.opacity(0.4),
            gridStrokeWidth: CGFloat(meta.gridStrokeWidth),
            snapToGrid: meta.snapToGrid
        ))
    }
    for i in boards.indices where boards[i].selectedLayerId == nil {
        boards[i].selectedLayerId = boards[i].layers.first?.id
    }
    return boards.isEmpty ? [BoardData()] : boards
}

// MARK: - Pave Content View

struct PaveContentView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var boards: [BoardData] = loadPaveBoards()
    @State private var selectedTab: Int = 0
    @State private var dashPhase: CGFloat = 0
    @State private var showDeleteConfirm = false
    @State private var renamingLayerId: UUID?
    @State private var renameText = ""
    @State private var lastMouseCanvas: CGPoint = .zero
    @State private var canvasViewSize: CGSize = .zero
    let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var board: BoardData { boards[selectedTab] }
    private var canAdd: Bool { boards.count < 5 }
    private var canRemove: Bool { boards.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            settingsBar
            Divider()

            HSplitView {
                canvasArea
                    .layoutPriority(1)
                layersSidebar
                    .frame(minWidth: 140, maxWidth: 220)
            }

            Divider()
            statusBar
        }
        .overlay(keyboardShortcuts)
        .onReceive(timer) { _ in dashPhase += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in savePaveBoards(boards) }
        .alert("Remove Board", isPresented: $showDeleteConfirm) {
            Button("Remove", role: .destructive) { removeBoard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove Board\(selectedTab + 1)? The canvas content will be lost.")
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            Button(action: confirmRemove) {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(4)
            .disabled(!canRemove)

            ForEach(boards.indices, id: \.self) { i in
                Button(action: { selectedTab = i }) {
                    Text("Board\(i + 1)")
                        .font(.system(size: 11, weight: selectedTab == i ? .semibold : .regular))
                        .foregroundColor(selectedTab == i ? .white : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(selectedTab == i ? Color.accentColor : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain).padding(4)
            }

            Button(action: addBoard) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(4)
            .disabled(!canAdd)

            Spacer()
        }
        .padding(.trailing, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
    }

    // MARK: - Settings Bar

    private var settingsBar: some View {
        HStack(spacing: 8) {
            Toggle("Grid", isOn: Binding(
                get: { boards[selectedTab].showGrid },
                set: { boards[selectedTab].showGrid = $0 }
            )).toggleStyle(.checkbox).font(.caption)

            Text("W:").foregroundColor(.secondary).font(.caption)
            TextField("px", value: Binding(
                get: { boards[selectedTab].gridWidth },
                set: { boards[selectedTab].gridWidth = max(1, $0) }
            ), formatter: NumberFormatter()).textFieldStyle(.roundedBorder).frame(width: 50)
            Text("H:").foregroundColor(.secondary).font(.caption)
            TextField("px", value: Binding(
                get: { boards[selectedTab].gridHeight },
                set: { boards[selectedTab].gridHeight = max(1, $0) }
            ), formatter: NumberFormatter()).textFieldStyle(.roundedBorder).frame(width: 50)

            ColorPicker("", selection: Binding(
                get: { boards[selectedTab].gridStrokeColor },
                set: { boards[selectedTab].gridStrokeColor = $0 }
            )).labelsHidden().frame(width: 16, height: 16).help("Grid stroke color")
            TextField("pt", value: Binding(
                get: { boards[selectedTab].gridStrokeWidth },
                set: { boards[selectedTab].gridStrokeWidth = max(0.1, $0) }
            ), formatter: NumberFormatter()).textFieldStyle(.roundedBorder).frame(width: 40).help("Grid stroke width")

            Toggle("Snap", isOn: Binding(
                get: { boards[selectedTab].snapToGrid },
                set: { boards[selectedTab].snapToGrid = $0 }
            )).toggleStyle(.checkbox).font(.caption).help("Snap pasted image center to nearest grid cell center")

            Divider().frame(height: 16)

            Text("Size").font(.caption).foregroundColor(.secondary)
            Text("W:").foregroundColor(.secondary).font(.caption)
            TextField("px", value: Binding(
                get: { boards[selectedTab].canvasWidth },
                set: { boards[selectedTab].canvasWidth = $0 }
            ), formatter: NumberFormatter()).textFieldStyle(.roundedBorder).frame(width: 60)
            Text("H:").foregroundColor(.secondary).font(.caption)
            TextField("px", value: Binding(
                get: { boards[selectedTab].canvasHeight },
                set: { boards[selectedTab].canvasHeight = $0 }
            ), formatter: NumberFormatter()).textFieldStyle(.roundedBorder).frame(width: 60)
            ColorPicker("", selection: Binding(
                get: { prefs.checkerColor2 },
                set: { prefs.checkerColor2 = $0 }
            )).labelsHidden().frame(width: 16, height: 16).help("Checker dark color")
            Spacer()
            Button("Clear") { clearBoard() }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // MARK: - Canvas Area

    private var canvasArea: some View {
        GeometryReader { geo in
            let b = boards[selectedTab]
            let cw = max(1, b.canvasWidth)
            let ch = max(1, b.canvasHeight)
            let scale = min(geo.size.width / cw, geo.size.height / ch)
            let drawW = cw * scale
            let drawH = ch * scale

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                ZStack(alignment: .topLeading) {
                    Checkerboard(width: drawW, height: drawH,
                                 tileW: prefs.checkerTileWidth, tileH: prefs.checkerTileHeight,
                                 color1: prefs.checkerColor1,
                                 color2: prefs.checkerColor2)

                    ForEach(b.layers) { layer in
                        if layer.isVisible, let img = layer.canvasImage {
                            Image(nsImage: img).resizable().interpolation(.none)
                                .frame(width: drawW, height: drawH)
                        }
                    }

                    if b.showGrid {
                        GridOverlay(width: drawW, height: drawH, gridW: b.gridWidth * scale, gridH: b.gridHeight * scale,
                                    strokeColor: b.gridStrokeColor, strokeWidth: b.gridStrokeWidth)
                    }

                    if let sr = b.selectionRect {
                        let sx = sr.origin.x * scale
                        let sy = sr.origin.y * scale
                        let sw = sr.width * scale
                        let sh = sr.height * scale
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4], dashPhase: dashPhase))
                            .foregroundColor(.blue)
                            .frame(width: sw, height: sh)
                            .position(x: sx + sw / 2, y: sy + sh / 2)
                    }

                    if let img = b.floatingImage, b.showFloating {
                        let fw = img.size.width * scale
                        let fh = img.size.height * scale
                        let fx = b.floatingOrigin.x * scale + b.dragOffset.width
                        let fy = b.floatingOrigin.y * scale + b.dragOffset.height
                        Image(nsImage: img).resizable().interpolation(.none)
                            .frame(width: fw, height: fh)
                            .position(x: fx + fw / 2, y: fy + fh / 2)
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4], dashPhase: dashPhase))
                            .foregroundColor(.blue)
                            .frame(width: fw, height: fh)
                            .position(x: fx + fw / 2, y: fy + fh / 2)
                    }
                }
                .frame(width: drawW, height: drawH)
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { canvasViewSize = proxy.size }
                })
                .onContinuousHover { phase in
                    if case .active(let pt) = phase {
                        lastMouseCanvas = pt
                    }
                }
                .gesture(canvasDragGesture(scale: scale))
                .onTapGesture { boardTapped() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    // MARK: - Canvas Gestures

    private func canvasDragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { val in
                if boards[selectedTab].isSelecting || (NSEvent.modifierFlags == [] && !boards[selectedTab].showFloating) {
                    if !boards[selectedTab].isSelecting {
                        boards[selectedTab].selectionStart = CGPoint(x: val.startLocation.x / scale, y: val.startLocation.y / scale)
                    }
                    let b = boards[selectedTab]
                    let start = b.selectionStart
                    let cur = CGPoint(x: val.location.x / scale, y: val.location.y / scale)
                    let rect = CGRect(x: min(start.x, cur.x), y: min(start.y, cur.y),
                                      width: abs(cur.x - start.x), height: abs(cur.y - start.y))
                    boards[selectedTab].selectionRect = rect
                    boards[selectedTab].isSelecting = true
                } else if boards[selectedTab].showFloating {
                    let b = boards[selectedTab]
                    if b.snapToGrid, let img = b.floatingImage {
                        let rawOrigin = CGPoint(x: b.floatingOrigin.x + val.translation.width / scale,
                                                 y: b.floatingOrigin.y + val.translation.height / scale)
                        let snapped = snappedOrigin(forRawOrigin: rawOrigin, imgSize: img.size, gridW: b.gridWidth, gridH: b.gridHeight)
                        boards[selectedTab].dragOffset = CGSize(width: (snapped.x - b.floatingOrigin.x) * scale,
                                                                 height: (snapped.y - b.floatingOrigin.y) * scale)
                    } else {
                        boards[selectedTab].dragOffset = val.translation
                    }
                }
            }
            .onEnded { val in
                if boards[selectedTab].isSelecting {
                    if let sr = boards[selectedTab].selectionRect, sr.width < 3 || sr.height < 3 {
                        boards[selectedTab].selectionRect = nil
                    }
                    boards[selectedTab].isSelecting = false
                } else if boards[selectedTab].showFloating {
                    let b = boards[selectedTab]
                    boards[selectedTab].floatingOrigin.x += b.dragOffset.width / scale
                    boards[selectedTab].floatingOrigin.y += b.dragOffset.height / scale
                    boards[selectedTab].dragOffset = .zero
                } else {
                    boards[selectedTab].selectionRect = nil
                }
            }
    }

    /// Given a proposed top-left origin (canvas coordinates, unscaled) for an image of `imgSize`,
    /// returns the origin adjusted so the image's *center* lands on the center of the nearest grid cell.
    private func snappedOrigin(forRawOrigin origin: CGPoint, imgSize: NSSize, gridW: CGFloat, gridH: CGFloat) -> CGPoint {
        guard gridW > 0, gridH > 0 else { return origin }
        let centerX = origin.x + imgSize.width / 2
        let centerY = origin.y + imgSize.height / 2
        let snappedCenterX = (floor(centerX / gridW) + 0.5) * gridW
        let snappedCenterY = (floor(centerY / gridH) + 0.5) * gridH
        return CGPoint(x: snappedCenterX - imgSize.width / 2, y: snappedCenterY - imgSize.height / 2)
    }

    private func boardTapped() {
        if boards[selectedTab].selectionRect != nil {
            boards[selectedTab].selectionRect = nil
        }
    }

    private func commitFloating(scale: CGFloat) {
        guard boards[selectedTab].showFloating,
              let img = boards[selectedTab].floatingImage,
              let layerIdx = boards[selectedTab].selectedLayerIndex else { return }
        pushUndo()
        let b = boards[selectedTab]
        let canvasSize = NSSize(width: b.canvasWidth, height: b.canvasHeight)
        let existing = boards[selectedTab].layers[layerIdx].canvasImage
        let rep = NSImage(size: canvasSize)
        rep.lockFocus()
        existing?.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        let pos = CGPoint(x: b.floatingOrigin.x + b.dragOffset.width / scale,
                          y: CGFloat(b.canvasHeight) - (b.floatingOrigin.y + b.dragOffset.height / scale) - img.size.height)
        img.draw(at: pos, from: .zero, operation: .sourceOver, fraction: 1)
        rep.unlockFocus()
        boards[selectedTab].layers[layerIdx].canvasImage = rep
        boards[selectedTab].floatingImage = nil
        boards[selectedTab].showFloating = false
        boards[selectedTab].dragOffset = .zero
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcuts: some View {
        HStack(spacing: 0) {
            Button("") { pasteImage() }.keyboardShortcut("v", modifiers: .command).opacity(0)
            Button("") { commitFloating(scale: 1) }.keyboardShortcut(.return, modifiers: []).opacity(0)
            Button("") { cancelFloating() }.keyboardShortcut(.escape, modifiers: []).opacity(0)
            Button("") { copySelection() }.keyboardShortcut("c", modifiers: .command).opacity(0)
            Button("") { clearSelection() }.keyboardShortcut("d", modifiers: .command).opacity(0)
            Button("") { undo() }.keyboardShortcut("z", modifiers: .command).opacity(0)
            Button("") { redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).opacity(0)
            Button("") { rotateFloatingCW() }.keyboardShortcut("r", modifiers: .command).opacity(0)
            Button("") { rotateFloatingCCW() }.keyboardShortcut("r", modifiers: [.command, .shift]).opacity(0)
            Button("") { flipFloatingH() }.keyboardShortcut("f", modifiers: .command).opacity(0)
            Button("") { flipFloatingV() }.keyboardShortcut("f", modifiers: [.command, .shift]).opacity(0)
        }
        .frame(width: 0, height: 0)
    }

    private func pasteImage() {
        guard let image = NSImage(pasteboard: .general),
               boards[selectedTab].selectedLayerIndex != nil else { return }
        let cw = boards[selectedTab].canvasWidth
        let ch = boards[selectedTab].canvasHeight
        let s = canvasViewSize.width > 0 ? min(canvasViewSize.width / cw, canvasViewSize.height / ch) : 1
        var origin = CGPoint(x: lastMouseCanvas.x / s, y: lastMouseCanvas.y / s)
        let b = boards[selectedTab]
        if b.snapToGrid {
            origin = snappedOrigin(forRawOrigin: origin, imgSize: image.size, gridW: b.gridWidth, gridH: b.gridHeight)
        }
        boards[selectedTab].floatingImage = image
        boards[selectedTab].floatingOrigin = origin
        boards[selectedTab].dragOffset = .zero
        boards[selectedTab].showFloating = true
        boards[selectedTab].selectionRect = nil
    }

    private func commitFloating() { commitFloating(scale: 1) }

    private func cancelFloating() {
        boards[selectedTab].floatingImage = nil
        boards[selectedTab].showFloating = false
        boards[selectedTab].dragOffset = .zero
    }

    private func rotateFloatingCW() {
        guard let img = boards[selectedTab].floatingImage, boards[selectedTab].showFloating else { return }
        let rotated = NSImage(size: NSSize(width: img.size.height, height: img.size.width))
        rotated.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: img.size.height / 2, y: img.size.width / 2)
        ctx.rotate(by: .pi / 2)
        img.draw(at: NSPoint(x: -img.size.width / 2, y: -img.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
        rotated.unlockFocus()
        boards[selectedTab].floatingImage = rotated
    }

    private func rotateFloatingCCW() {
        guard let img = boards[selectedTab].floatingImage, boards[selectedTab].showFloating else { return }
        let rotated = NSImage(size: NSSize(width: img.size.height, height: img.size.width))
        rotated.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: img.size.height / 2, y: img.size.width / 2)
        ctx.rotate(by: -.pi / 2)
        img.draw(at: NSPoint(x: -img.size.width / 2, y: -img.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
        rotated.unlockFocus()
        boards[selectedTab].floatingImage = rotated
    }

    private func flipFloatingH() {
        guard let img = boards[selectedTab].floatingImage, boards[selectedTab].showFloating else { return }
        let flipped = NSImage(size: img.size)
        flipped.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: img.size.width, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        flipped.unlockFocus()
        boards[selectedTab].floatingImage = flipped
    }

    private func flipFloatingV() {
        guard let img = boards[selectedTab].floatingImage, boards[selectedTab].showFloating else { return }
        let flipped = NSImage(size: img.size)
        flipped.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: 0, y: img.size.height)
        ctx.scaleBy(x: 1, y: -1)
        img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        flipped.unlockFocus()
        boards[selectedTab].floatingImage = flipped
    }

    private func copySelection() {
        guard let sr = boards[selectedTab].selectionRect,
              let layerIdx = boards[selectedTab].selectedLayerIndex,
              let canvas = boards[selectedTab].layers[layerIdx].canvasImage else { return }
        let cropped = NSImage(size: NSSize(width: sr.width, height: sr.height))
        cropped.lockFocus()
        canvas.draw(at: NSPoint(x: -sr.origin.x, y: -(canvas.size.height - sr.origin.y - sr.height)),
                    from: .zero, operation: .sourceOver, fraction: 1)
        cropped.unlockFocus()
        copyToPasteboard(cropped)
    }

    private func clearSelection() { boards[selectedTab].selectionRect = nil }

    // MARK: - Board Actions

    private func addBoard() {
        guard canAdd else { return }
        var newBoard = BoardData()
        newBoard.selectedLayerId = newBoard.layers.first?.id
        boards.append(newBoard)
        selectedTab = boards.count - 1
    }

    private func confirmRemove() {
        if !board.layers.isEmpty && board.layers.contains(where: { $0.canvasImage != nil }) {
            showDeleteConfirm = true
        } else {
            removeBoard()
        }
    }

    private func removeBoard() {
        boards.remove(at: selectedTab)
        if selectedTab >= boards.count { selectedTab = boards.count - 1 }
    }

    private func clearBoard() {
        guard let idx = boards[selectedTab].selectedLayerIndex else { return }
        pushUndo()
        boards[selectedTab].layers[idx].canvasImage = nil
    }

    // MARK: - Undo/Redo

    private func pushUndo() {
        boards[selectedTab].undoStack.append(boards[selectedTab].layers)
        if boards[selectedTab].undoStack.count > 50 { boards[selectedTab].undoStack.removeFirst() }
        boards[selectedTab].redoStack.removeAll()
    }

    // MARK: - Layers Sidebar

    private var layersSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Layers").font(.caption).foregroundColor(.secondary).padding(.horizontal, 8).padding(.top, 6)
            List(boards[selectedTab].layers.indices, id: \.self, selection: Binding(
                get: { boards[selectedTab].selectedLayerIndex },
                set: { if let i = $0 { boards[selectedTab].selectedLayerId = boards[selectedTab].layers[i].id } }
            )) { idx in
                layerRow(idx: idx)
            }
            .listStyle(.plain)

            Divider()
            Button(action: addLayer) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain).padding(.horizontal, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func addLayer() {
        pushUndo()
        let num = boards[selectedTab].layers.count + 1
        boards[selectedTab].layers.append(BoardLayer(name: "Layer \(num)"))
        boards[selectedTab].selectedLayerId = boards[selectedTab].layers.last?.id
    }

    private func removeLayer(_ idx: Int) {
        guard boards[selectedTab].layers.count > 1 else { return }
        pushUndo()
        let id = boards[selectedTab].layers[idx].id
        boards[selectedTab].layers.remove(at: idx)
        if boards[selectedTab].selectedLayerId == id {
            boards[selectedTab].selectedLayerId = boards[selectedTab].layers.first?.id
        }
    }

    private func copyLayerToClipboard(_ layer: BoardLayer) {
        guard let img = layer.canvasImage else { return }
        copyToPasteboard(img)
    }

    private func startRename(_ id: UUID) {
        renamingLayerId = id
        renameText = boards[selectedTab].layers.first(where: { $0.id == id })?.name ?? ""
    }

    private func finishRename(_ id: UUID) {
        if let idx = boards[selectedTab].layers.firstIndex(where: { $0.id == id }) {
            boards[selectedTab].layers[idx].name = renameText
        }
        renamingLayerId = nil
        renameText = ""
    }

    private func layerRow(idx: Int) -> some View {
        let layer = boards[selectedTab].layers[idx]
        let isSelected = boards[selectedTab].selectedLayerId == layer.id
        return HStack(spacing: 6) {
            Button(action: { boards[selectedTab].layers[idx].isVisible.toggle() }) {
                Image(systemName: boards[selectedTab].layers[idx].isVisible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(boards[selectedTab].layers[idx].isVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain).frame(width: 16)

            ZStack {
                Color(nsColor: .controlBackgroundColor)
                    .frame(width: 26, height: 26)
                    .cornerRadius(2)
                if let img = layer.canvasImage {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26).clipped()
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(nsColor: .gridColor)))

            if renamingLayerId == layer.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit { finishRename(layer.id) }
            } else {
                Text(layer.name).font(.system(size: 11)).lineLimit(1)
                    .onLongPressGesture(minimumDuration: 0.5) { startRename(layer.id) }
            }

            Spacer()

            if boards[selectedTab].layers.count > 1 {
                Button(action: { removeLayer(idx) }) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(isSelected ? Rectangle().frame(width: 3).foregroundColor(.accentColor) : nil, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { copyLayerToClipboard(layer) }
        .onTapGesture { boards[selectedTab].selectedLayerId = layer.id }
        .contextMenu {
            Button("Rename") { startRename(layer.id) }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("Board \(selectedTab + 1) · \(Int(board.canvasWidth))×\(Int(board.canvasHeight))")
                .font(.caption).foregroundColor(.secondary)
            if board.showFloating { Text("· Floating").font(.caption).foregroundColor(.orange) }
            Spacer()
            HStack(spacing: 4) {
                Button("Undo") { undo() }.font(.caption)
                Button("Redo") { redo() }.font(.caption)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func undo() {
        guard !boards[selectedTab].undoStack.isEmpty else { return }
        boards[selectedTab].redoStack.append(boards[selectedTab].layers)
        boards[selectedTab].layers = boards[selectedTab].undoStack.removeLast()
    }

    private func redo() {
        guard !boards[selectedTab].redoStack.isEmpty else { return }
        boards[selectedTab].undoStack.append(boards[selectedTab].layers)
        boards[selectedTab].layers = boards[selectedTab].redoStack.removeLast()
    }

    // MARK: - Grid Overlay

    private struct Checkerboard: View {
        let width: CGFloat
        let height: CGFloat
        let tileW: CGFloat
        let tileH: CGFloat
        let color1: Color
        let color2: Color

        var body: some View {
            Canvas { context, size in
                let cols = Int(ceil(size.width / tileW))
                let rows = Int(ceil(size.height / tileH))
                for r in 0..<rows {
                    for c in 0..<cols {
                        let rect = CGRect(x: CGFloat(c) * tileW, y: CGFloat(r) * tileH, width: tileW, height: tileH)
                        context.fill(Path(rect), with: .color((c + r) % 2 == 0 ? color1 : color2))
                    }
                }
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)
        }
    }

    private struct GridOverlay: View {
        let width: CGFloat
        let height: CGFloat
        let gridW: CGFloat
        let gridH: CGFloat
        let strokeColor: Color
        let strokeWidth: CGFloat

        var body: some View {
            Canvas { context, size in
                var x: CGFloat = gridW
                while x < size.width {
                    context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(strokeColor), lineWidth: strokeWidth)
                    x += gridW
                }
                var y: CGFloat = gridH
                while y < size.height {
                    context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(strokeColor), lineWidth: strokeWidth)
                    y += gridH
                }
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)
        }
    }
}
