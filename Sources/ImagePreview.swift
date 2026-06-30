import SwiftUI

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
                                DragGesture(minimumDistance: 2)
                                    .onChanged { handleGlobalDrag(value: $0) }
                                    .onEnded { _ in isSelecting = false; isDragging = false; isResizing = false; resizeEdge = .none }
                            )

                        if settings.showGrid {
                            GridView(gridWidth: settings.parsedGridWidth, gridHeight: settings.parsedGridHeight,
                                     imageWidth: item.image.size.width, imageHeight: item.image.size.height,
                                     currentScale: displayScale,
                                     color: settings.gridColor, strokeWidth: settings.parsedGridStrokeWidth,
                                     offsetX: settings.gridOffsetX, offsetY: settings.gridOffsetY)
                            .allowsHitTesting(false)
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
                                onColorChange: { settings.selectionColorHex = $0.toHex() },
                                onAddSprite: addSpriteFromSelection
                            )
                        }

                        Button("") { addSpriteFromSelection() }
                            .keyboardShortcut("s", modifiers: []).opacity(0).frame(width: 0, height: 0)
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
        let color: Color
        let strokeWidth: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        var body: some View {
            Canvas { context, size in
                let scaledGW = CGFloat(max(1, gridWidth)) * currentScale
                let scaledGH = CGFloat(max(1, gridHeight)) * currentScale
                let startX = offsetX * currentScale
                let startY = offsetY * currentScale

                var x: CGFloat = startX
                while x <= size.width {
                    context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(color), lineWidth: strokeWidth)
                    x += scaledGW
                }
                var y: CGFloat = startY
                while y <= size.height {
                    context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(color), lineWidth: strokeWidth)
                    y += scaledGH
                }
            }.frame(width: imageWidth * currentScale, height: imageHeight * currentScale)
        }
    }
    
    private func handleGlobalDrag(value: DragGesture.Value) {
        let canvasLocation = value.location
        let currentPoint = CGPoint(x: canvasLocation.x / displayScale, y: canvasLocation.y / displayScale)

        if isDragging || isResizing {
            var delta = CGPoint(x: currentPoint.x - dragStartPoint.x, y: currentPoint.y - dragStartPoint.y)
            if isDragging && NSEvent.modifierFlags.contains(.shift) {
                if abs(delta.x) >= abs(delta.y) { delta.y = 0 } else { delta.x = 0 }
            }
            if isResizing {
                selectionRect = snapRectToGrid(applyResizeToRect(dragStartRect, delta: delta, edge: resizeEdge))
            } else {
                let newX = max(0, min(dragStartRect.origin.x + delta.x, item.image.size.width - dragStartRect.width))
                let newY = max(0, min(dragStartRect.origin.y + delta.y, item.image.size.height - dragStartRect.height))
                selectionRect = snapRectToGrid(CGRect(x: newX, y: newY, width: dragStartRect.width, height: dragStartRect.height))
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
                selectionRect = snapRectToGrid(CGRect(
                    x: max(0, min(currentPoint.x - clampedW / 2, item.image.size.width - clampedW)),
                    y: max(0, min(currentPoint.y - clampedH / 2, item.image.size.height - clampedH)),
                    width: clampedW, height: clampedH
                ))
            } else {
                let x = max(0, min(startPoint.x, currentPoint.x))
                let y = max(0, min(startPoint.y, currentPoint.y))
                let width = max(1, min(abs(currentPoint.x - startPoint.x), item.image.size.width - x))
                let height = max(1, min(abs(currentPoint.y - startPoint.y), item.image.size.height - y))
                selectionRect = snapRectToGrid(CGRect(x: x, y: y, width: width, height: height))
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
            selectionRect = snapRectToGrid(CGRect(x: max(0, min(startPoint.x, item.image.size.width - clampedW)),
                                   y: max(0, min(startPoint.y, item.image.size.height - clampedH)), width: clampedW, height: clampedH))
        } else {
            selectionRect = snapRectToGrid(CGRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1))
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

    private func snapRectToGrid(_ rect: CGRect) -> CGRect {
        guard settings.snapToGrid else { return rect }
        let gw = CGFloat(max(1, settings.parsedGridWidth))
        let gh = CGFloat(max(1, settings.parsedGridHeight))
        let ox = settings.gridOffsetX
        let oy = settings.gridOffsetY
        let snapX = { (px: CGFloat) -> CGFloat in round((px - ox) / gw) * gw + ox }
        let snapY = { (py: CGFloat) -> CGFloat in round((py - oy) / gh) * gh + oy }
        var r = rect
        let sminX = snapX(r.minX); let sminY = snapY(r.minY)
        let smaxX = snapX(r.maxX); let smaxY = snapY(r.maxY)
        r.origin.x = sminX; r.origin.y = sminY
        r.size.width = max(1, smaxX - sminX); r.size.height = max(1, smaxY - sminY)
        return r
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

    private func addSpriteFromSelection() {
        guard let rect = selectionRect,
              let cgImage = item.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let sX = CGFloat(cgImage.width) / item.image.size.width
        let sY = CGFloat(cgImage.height) / item.image.size.height
        let pixelRect = CGRect(x: Int(rect.origin.x * sX), y: Int(rect.origin.y * sY),
                               width: Int(rect.width * sX), height: Int(rect.height * sY))

        guard var cropped = cgImage.cropping(to: pixelRect) else { return }

        let store = AnimationStore.shared
        if let anim = store.selectedAnimation, anim.frameWidth > 0, anim.frameHeight > 0 {
            let fw = Int(anim.frameWidth)
            let fh = Int(anim.frameHeight)
            if cropped.width > fw || cropped.height > fh {
                let cx = (cropped.width - fw) / 2
                let cy = (cropped.height - fh) / 2
                let cropRect = CGRect(x: max(0, cx), y: max(0, cy), width: fw, height: fh)
                if let centerCropped = cropped.cropping(to: cropRect) { cropped = centerCropped }
            } else if cropped.width < fw || cropped.height < fh {
                let hex = anim.bgColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                var int: UInt64 = 0
                Scanner(string: hex).scanHexInt64(&int)
                let r = CGFloat((int >> 16) & 0xFF) / 255
                let g = CGFloat((int >> 8) & 0xFF) / 255
                let b = CGFloat(int & 0xFF) / 255
                let cs = cropped.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
                let ctx = CGContext(data: nil, width: fw, height: fh, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                if let ctx = ctx {
                    ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: 0, width: fw, height: fh))
                    let dx = (fw - cropped.width) / 2
                    let dy = (fh - cropped.height) / 2
                    ctx.draw(cropped, in: CGRect(x: dx, y: dy, width: cropped.width, height: cropped.height))
                    if let padded = ctx.makeImage() { cropped = padded }
                }
            }
        }

        let spritesDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ImageViewer").appendingPathComponent("Sprites")
        try? FileManager.default.createDirectory(at: spritesDir, withIntermediateDirectories: true)

        let url = spritesDir.appendingPathComponent("sprite-\(UUID().uuidString).png")
        let bitmap = NSBitmapImageRep(cgImage: cropped)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)

        store.addImage(url.path)
    }

}
