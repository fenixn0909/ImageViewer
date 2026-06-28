import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ImageStore
    @StateObject private var settings = SettingsManager.shared
    @State private var isTargeted = false
    @State private var errorToShow: ImageLoadError?
    @State private var zoomPercent: Int = 100

    var selectedImage: ImageItem? { store.getSelectedImage() }

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
        .onReceive(store.$lastError) { error in errorToShow = error }
        .alert("Error", isPresented: .init(get: { errorToShow != nil }, set: { if !$0 { errorToShow = nil } })) {
            Text(errorToShow?.localizedDescription ?? "Unknown error")
        }
        .background(arrowKeyButtons)
    }

    @ViewBuilder
    private var arrowKeyButtons: some View {
        HStack(spacing: 0) {
            Button("") { navigateToPrevious() }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { navigateToNext() }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { zoomIn() }.keyboardShortcut(.upArrow, modifiers: []).opacity(0)
            Button("") { zoomOut() }.keyboardShortcut(.downArrow, modifiers: []).opacity(0)
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
        HStack(spacing: 12) {
            Toggle("Fixed Size", isOn: $settings.fixedSelectionEnabled)
                .toggleStyle(.checkbox)
            Text("W:").foregroundColor(.secondary)
            TextField("px", text: $settings.fixedSelectionWidth)
                .textFieldStyle(.roundedBorder).frame(width: 60).disabled(!settings.fixedSelectionEnabled)
            Text("H:").foregroundColor(.secondary)
            TextField("px", text: $settings.fixedSelectionHeight)
                .textFieldStyle(.roundedBorder).frame(width: 60).disabled(!settings.fixedSelectionEnabled)
            
            Button("Apply") {
                let w = settings.parsedFixedWidth
                let h = settings.parsedFixedHeight
                if w > 0 && h > 0 {
                    NotificationCenter.default.post(name: .applyFixedSize, object: CGSize(width: w, height: h))
                }
            }
            .disabled(!settings.fixedSelectionEnabled || settings.parsedFixedWidth <= 0 || settings.parsedFixedHeight <= 0)

            Divider().frame(height: 16)

            Toggle("Grid", isOn: $settings.showGrid).toggleStyle(.checkbox)
            Text("W:").foregroundColor(.secondary)
            TextField("px", text: $settings.gridWidth).textFieldStyle(.roundedBorder).frame(width: 50)
            Text("H:").foregroundColor(.secondary)
            TextField("px", text: $settings.gridHeight).textFieldStyle(.roundedBorder).frame(width: 50)

            Divider().frame(height: 16)
            Toggle("Keep Zoom", isOn: $settings.keepZoom).toggleStyle(.checkbox)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
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
                    if let url = url { Task { await ImageLoader.shared.loadAndSend(url: url) } }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        Task { @MainActor in ImageStore.shared.addImage(image, thumbnail: nil, path: "dropped-\(UUID().uuidString)") }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Subviews

struct FileInfoBar: View {
    let item: ImageItem?
    let zoomPercent: Int?

    var body: some View {
        HStack {
            if let item = item {
                Text(fileName).font(.system(size: 11))
                Divider().frame(height: 12)
                Text("\(Int(item.image.size.width)) \u{00D7} \(Int(item.image.size.height)) px").font(.system(size: 11))
                Divider().frame(height: 12)
                Text(fileSize).font(.system(size: 11))

                if !item.filePath.hasPrefix("clipboard") && !item.filePath.hasPrefix("dropped") {
                    Divider().frame(height: 12)
                    Text(item.filePath).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()
                if let zoomPercent = zoomPercent {
                    Divider().frame(height: 12)
                    Text("\(zoomPercent)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4).background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .top)
    }

    var fileSize: String {
        guard let item = item else { return "" }
        if item.filePath.hasPrefix("clipboard") || item.filePath.hasPrefix("dropped") { return "Unknown" }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: item.filePath),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileName: String {
        guard let item = item else { return "" }
        return item.filePath.hasPrefix("clipboard") || item.filePath.hasPrefix("dropped") ? "(Clipboard/Pasted)" : URL(fileURLWithPath: item.filePath).lastPathComponent
    }
}

struct GallerySidebar: View {
    @ObservedObject var store: ImageStore
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.images.isEmpty ? "Gallery" : "Images (\(store.images.count))").font(.headline)
                Spacer()
            }.padding(8).background(Color(nsColor: .controlBackgroundColor))

            if store.images.isEmpty {
                VStack { Spacer(); Text("No images").foregroundColor(.secondary).font(.caption); Spacer() }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(store.images) { item in
                            ThumbnailView(
                                image: item.thumbnail ?? item.image,
                                isSelected: store.selectedImageId == item.id,
                                onRemove: { store.removeImage(item.id) }
                            ).onTapGesture { store.selectedImageId = item.id }
                        }
                    }.padding(8)
                }.frame(maxHeight: .infinity)
            }
            DropAddButton(isTargeted: $isTargeted)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct DropAddButton: View {
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundColor(isTargeted ? .blue : .gray)
            Text("Add").font(.caption2).foregroundColor(isTargeted ? .blue : .secondary)
        }
        .frame(height: 60).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5)))
        .background(RoundedRectangle(cornerRadius: 8).fill(isTargeted ? Color.blue.opacity(0.1) : Color.clear))
        .padding(8).contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url { Task { await ImageLoader.shared.loadAndSend(url: url) } }
                    }
                }
            }
            return true
        }
    }
}

struct ThumbnailView: View {
    let image: NSImage
    let isSelected: Bool
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 50)
                .clipped().cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.white)
                        .background(Circle().fill(Color.red).frame(width: 14, height: 14))
                }.buttonStyle(.plain).offset(x: 4, y: -4)
            }
        }.onHover { isHovered = $0 }
    }
}

struct ImagePreview: View {
    let item: ImageItem
    let onZoomChange: (Int) -> Void
    @ObservedObject private var settings = SettingsManager.shared
    
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

    private var displayScale: CGFloat { fitScale * zoomLevel }

    enum ResizeEdge { case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        
                        Image(nsImage: item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: item.image.size.width * displayScale, height: item.image.size.height * displayScale)
                            .allowsHitTesting(false)
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: item.image.size.width * displayScale, height: item.image.size.height * displayScale)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { handleGlobalDrag(value: $0) }
                                    .onEnded { _ in isSelecting = false; isDragging = false; isResizing = false; resizeEdge = .none }
                            )

                        if settings.showGrid {
                            GridView(gridWidth: settings.parsedGridWidth, gridHeight: settings.parsedGridHeight,
                                     imageWidth: item.image.size.width, imageHeight: item.image.size.height, currentScale: displayScale)
                        }

                        if let rect = selectionRect, rect.width > 5 && rect.height > 5 {
                            let scaledRect = CGRect(x: rect.origin.x * displayScale, y: rect.origin.y * displayScale,
                                                    width: rect.width * displayScale, height: rect.height * displayScale)
                            
                            SelectionOverlay(
                                rect: scaledRect,
                                selectionColor: settings.selectionColor,
                                isFixedSize: settings.fixedSelectionEnabled,
                                onCopy: copySelection,
                                onClear: { selectionRect = nil },
                                onColorChange: { settings.selectionColorHex = $0.toHex() }
                            )
                        }
                    }
                    .frame(width: max(item.image.size.width * displayScale, geometry.size.width),
                           height: max(item.image.size.height * displayScale, geometry.size.height))
                    .contentShape(Rectangle())
                    .gesture(MagnificationGesture()
                        .onChanged { zoomLevel = max(0.1, min(50, lastZoomLevel * $0)) }
                        .onEnded { _ in lastZoomLevel = zoomLevel })
                    .onAppear { updateImageFrame(imageSize: item.image.size, viewSize: geometry.size) }
                    .onChange(of: geometry.size) { newSize in updateImageFrame(imageSize: item.image.size, viewSize: newSize) }
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onChange(of: item.id) { _ in
            selectionRect = nil
            if !settings.keepZoom { zoomLevel = 1.0; lastZoomLevel = 1.0 }
        }
        .onChange(of: displayScale) { _ in onZoomChange(Int((displayScale * 100).rounded())) }
        .onReceive(NotificationCenter.default.publisher(for: .copySelection)) { _ in copySelection() }
        .onReceive(NotificationCenter.default.publisher(for: .clearSelection)) { _ in selectionRect = nil }
        .onReceive(NotificationCenter.default.publisher(for: .applyFixedSize)) { notification in
            if let size = notification.object as? CGSize {
                let clampedWidth = min(size.width, item.image.size.width)
                let clampedHeight = min(size.height, item.image.size.height)
                let x = (item.image.size.width - clampedWidth) / 2
                let y = (item.image.size.height - clampedHeight) / 2
                selectionRect = CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            zoomLevel = max(0.1, min(50, zoomLevel * 1.05))
            lastZoomLevel = zoomLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            zoomLevel = max(0.1, min(50, zoomLevel / 1.05))
            lastZoomLevel = zoomLevel
        }
    }

    struct GridView: View {
        let gridWidth: Int
        let gridHeight: Int
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        let currentScale: CGFloat

        var body: some View {
            Canvas { context, size in
                let scaledGW = CGFloat(max(1, gridWidth)) * currentScale
                let scaledGH = CGFloat(max(1, gridHeight)) * currentScale
                let lineColor = Color.white.opacity(0.5)

                var x: CGFloat = 0
                while x <= size.width {
                    context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(lineColor), lineWidth: 1)
                    x += scaledGW
                }
                var y: CGFloat = 0
                while y <= size.height {
                    context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(lineColor), lineWidth: 1)
                    y += scaledGH
                }
            }.frame(width: imageWidth * currentScale, height: imageHeight * currentScale)
        }
    }
    
    private func handleGlobalDrag(value: DragGesture.Value) {
        let canvasLocation = value.location
        let currentPoint = CGPoint(x: canvasLocation.x / displayScale, y: canvasLocation.y / displayScale)

        if isDragging || isResizing {
            let delta = CGPoint(x: currentPoint.x - dragStartPoint.x, y: currentPoint.y - dragStartPoint.y)
            if isResizing {
                selectionRect = applyResizeToRect(dragStartRect, delta: delta, edge: resizeEdge)
            } else {
                let newX = max(0, min(dragStartRect.origin.x + delta.x, item.image.size.width - dragStartRect.width))
                let newY = max(0, min(dragStartRect.origin.y + delta.y, item.image.size.height - dragStartRect.height))
                selectionRect = CGRect(x: newX, y: newY, width: dragStartRect.width, height: dragStartRect.height)
            }
            return
        }

        if isSelecting {
            let fw = settings.parsedFixedWidth
            let fh = settings.parsedFixedHeight
            let fixedMode = settings.fixedSelectionEnabled && fw > 0 && fh > 0

            if fixedMode {
                let clampedW = min(CGFloat(fw), item.image.size.width)
                let clampedH = min(CGFloat(fh), item.image.size.height)
                selectionRect = CGRect(
                    x: max(0, min(currentPoint.x - clampedW / 2, item.image.size.width - clampedW)),
                    y: max(0, min(currentPoint.y - clampedH / 2, item.image.size.height - clampedH)),
                    width: clampedW, height: clampedH
                )
            } else {
                let x = max(0, min(startPoint.x, currentPoint.x))
                let y = max(0, min(startPoint.y, currentPoint.y))
                let width = max(1, min(abs(currentPoint.x - startPoint.x), item.image.size.width - x))
                let height = max(1, min(abs(currentPoint.y - startPoint.y), item.image.size.height - y))
                selectionRect = CGRect(x: x, y: y, width: width, height: height)
            }
            return
        }

        if let selRect = selectionRect {
            let scaledRect = CGRect(x: selRect.origin.x * displayScale, y: selRect.origin.y * displayScale,
                                    width: selRect.width * displayScale, height: selRect.height * displayScale)

            if !settings.fixedSelectionEnabled {
                let edge = getEdge(canvasLocation, rect: scaledRect, tolerance: 12)
                if edge != .none {
                    isResizing = true
                    resizeEdge = edge
                    dragStartRect = selRect
                    dragStartPoint = currentPoint
                    return
                }
            }

            if scaledRect.contains(canvasLocation) {
                isDragging = true
                dragStartRect = selRect
                dragStartPoint = currentPoint
                return
            }
        }

        isSelecting = true
        startPoint = CGPoint(x: max(0, min(currentPoint.x, item.image.size.width)),
                             y: max(0, min(currentPoint.y, item.image.size.height)))

        let fw = settings.parsedFixedWidth
        let fh = settings.parsedFixedHeight
        let fixedMode = settings.fixedSelectionEnabled && fw > 0 && fh > 0

        if fixedMode {
            let clampedW = min(CGFloat(fw), item.image.size.width)
            let clampedH = min(CGFloat(fh), item.image.size.height)
            selectionRect = CGRect(x: max(0, min(startPoint.x, item.image.size.width - clampedW)),
                                   y: max(0, min(startPoint.y, item.image.size.height - clampedH)), width: clampedW, height: clampedH)
        } else {
            selectionRect = CGRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1)
        }
    }

    private func getEdge(_ point: CGPoint, rect: CGRect, tolerance: CGFloat) -> ResizeEdge {
        let closeL = abs(point.x - rect.minX) < tolerance, closeR = abs(point.x - rect.maxX) < tolerance
        let closeT = abs(point.y - rect.minY) < tolerance, closeB = abs(point.y - rect.maxY) < tolerance
        if closeL && closeT { return .topLeft }; if closeR && closeT { return .topRight }
        if closeL && closeB { return .bottomLeft }; if closeR && closeB { return .bottomRight }
        if closeL { return .left }; if closeR { return .right }; if closeT { return .top }; if closeB { return .bottom }
        return .none
    }

    private func applyResizeToRect(_ rect: CGRect, delta: CGPoint, edge: ResizeEdge) -> CGRect {
        var r = rect
        switch edge {
        case .left:
            let nW = r.width - delta.x
            if nW > 10 && r.origin.x + delta.x >= 0 {
                r = CGRect(x: r.origin.x + delta.x, y: r.origin.y, width: nW, height: r.height)
            }
        case .right:
            r.size.width = max(10, min(r.width + delta.x, item.image.size.width - r.origin.x))
        case .top:
            let nH = r.height - delta.y
            if nH > 10 && r.origin.y + delta.y >= 0 {
                r = CGRect(x: r.origin.x, y: r.origin.y + delta.y, width: r.width, height: nH)
            }
        case .bottom:
            r.size.height = max(10, min(r.height + delta.y, item.image.size.height - r.origin.y))
        case .topLeft:
            let nW = r.width - delta.x
            let nH = r.height - delta.y
            if nW > 10 && r.origin.x + delta.x >= 0 { r.origin.x += delta.x; r.size.width = nW }
            if nH > 10 && r.origin.y + delta.y >= 0 { r.origin.y += delta.y; r.size.height = nH }
        case .topRight:
            let nH = r.height - delta.y
            r.size.width = max(10, min(r.width + delta.x, item.image.size.width - r.origin.x))
            if nH > 10 && r.origin.y + delta.y >= 0 { r.origin.y += delta.y; r.size.height = nH }
        case .bottomLeft:
            let nW = r.width - delta.x
            if nW > 10 && r.origin.x + delta.x >= 0 { r.origin.x += delta.x; r.size.width = nW }
            r.size.height = max(10, min(r.height + delta.y, item.image.size.height - r.origin.y))
        case .bottomRight:
            r.size.width = max(10, min(r.width + delta.x, item.image.size.width - r.origin.x))
            r.size.height = max(10, min(r.height + delta.y, item.image.size.height - r.origin.y))
        case .none: break
        }
        return r
    }

    private func updateImageFrame(imageSize: CGSize, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return }
        fitScale = (imageSize.width / imageSize.height > viewSize.width / viewSize.height) ? (viewSize.width / imageSize.width) : (viewSize.height / imageSize.height)
    }
    
    private func copySelection() {
        guard let rect = selectionRect,
              let cgImage = item.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let sX = CGFloat(cgImage.width) / item.image.size.width
        let sY = CGFloat(cgImage.height) / item.image.size.height
        let pixelRect = CGRect(x: Int(rect.origin.x * sX), y: Int(rect.origin.y * sY),
                               width: Int(rect.width * sX), height: Int(rect.height * sY))

        guard let cropped = cgImage.cropping(to: pixelRect) else { return }
        let finalImage = NSImage(cgImage: cropped, size: NSSize(width: Int(rect.width), height: Int(rect.height)))
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }

    struct SelectionOverlay: View {
        let rect: CGRect
        let selectionColor: Color
        let isFixedSize: Bool
        let onCopy: () -> Void
        let onClear: () -> Void
        let onColorChange: (Color) -> Void

        var body: some View {
            ZStack {
                Rectangle().fill(selectionColor.opacity(0.2))
                Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4])).foregroundColor(selectionColor)
                
                if !isFixedSize {
                    Group {
                        node().position(x: 0, y: 0)
                        node().position(x: rect.width / 2, y: 0)
                        node().position(x: rect.width, y: 0)
                        
                        node().position(x: 0, y: rect.height / 2)
                        node().position(x: rect.width, y: rect.height / 2)
                        
                        node().position(x: 0, y: rect.height)
                        node().position(x: rect.width / 2, y: rect.height)
                        node().position(x: rect.width, y: rect.height)
                    }
                }
            }
            .allowsHitTesting(false)
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .overlay(alignment: .bottom) {
                HStack(spacing: 24) {
                    Button(action: onCopy) { Image(systemName: "doc.on.doc").font(.system(size: 20)) }
                        .buttonStyle(.plain)
                    
                    ColorPicker("", selection: Binding(
                        get: { selectionColor },
                        set: { onColorChange($0) }
                    ))
                    .labelsHidden()
                    .frame(width: 16, height: 16)
                    
                    Button(action: onClear) { Image(systemName: "xmark").font(.system(size: 12)) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selectionColor.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(6)
                .fixedSize()
                .offset(y: 38)
            }
            .offset(x: rect.minX, y: rect.minY) 
        }
        
        private func node() -> some View {
            Rectangle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .border(selectionColor, width: 2)
        }
    }
}