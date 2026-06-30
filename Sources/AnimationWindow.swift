import AppKit
import SwiftUI

final class AnimationPanelController: NSWindowController {
    static let shared = AnimationPanelController()

    private init() {
        let savedFrame = Self.loadFrame()
        let win = NSWindow(
            contentRect: savedFrame ?? NSRect(x: 0, y: 0, width: 260, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Animation"
        win.level = .normal
        win.hidesOnDeactivate = false
        win.minSize = NSSize(width: 200, height: 400)
        win.maxSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        let hostingView = NSHostingView(rootView: AnimationContentView())
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView
        super.init(window: win)
        if let frame = savedFrame { win.setFrame(frame, display: false) }
        if UserDefaults.standard.bool(forKey: "animWindowVisible") { win.makeKeyAndOrderFront(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(saveState), name: NSApplication.willTerminateNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func saveState() {
        guard let win = window else { return }
        UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: "animWindowFrame")
        UserDefaults.standard.set(win.isVisible, forKey: "animWindowVisible")
    }

    private static func loadFrame() -> NSRect? {
        guard let str = UserDefaults.standard.string(forKey: "animWindowFrame") else { return nil }
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

// MARK: - Animation Model

struct AnimationData: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var imagePaths: [String] = []
    var frameWidth: CGFloat = 0
    var frameHeight: CGFloat = 0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var bgColorHex: String = "#000000"
    var transparentBg: Bool = false
}

// MARK: - Animation Store

@MainActor
final class AnimationStore: ObservableObject {
    static let shared = AnimationStore()
    @Published var animations: [AnimationData] = []
    @Published var selectedAnimationId: UUID?

    private let appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ImageViewer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var saveURL: URL { appSupportDir.appendingPathComponent("animations.json") }

    private init() { load() }

    func add(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !animations.contains(where: { $0.name == trimmed }) else { return }
        let anim = AnimationData(name: trimmed)
        animations.append(anim)
        if selectedAnimationId == nil { selectedAnimationId = anim.id }
        save()
    }

    func remove(_ id: UUID) {
        animations.removeAll { $0.id == id }
        if selectedAnimationId == id { selectedAnimationId = animations.first?.id }
        save()
    }

    func addImage(_ path: String) {
        guard let id = selectedAnimationId, let idx = animations.firstIndex(where: { $0.id == id }),
              !animations[idx].imagePaths.contains(path) else { return }
        let wasEmpty = animations[idx].imagePaths.isEmpty
        animations[idx].imagePaths.append(path)
        if wasEmpty, let size = imageSize(at: path) {
            animations[idx].frameWidth = size.width
            animations[idx].frameHeight = size.height
        }
        save()
    }

    func removeImage(_ path: String, from animationId: UUID) {
        guard let idx = animations.firstIndex(where: { $0.id == animationId }) else { return }
        animations[idx].imagePaths.removeAll { $0 == path }
        save()
    }

    var selectedAnimation: AnimationData? {
        guard let id = selectedAnimationId else { return nil }
        return animations.first { $0.id == id }
    }

    var selectedAnimationIndex: Int? {
        guard let id = selectedAnimationId else { return nil }
        return animations.firstIndex(where: { $0.id == id })
    }

    var selectedAnimationBinding: Binding<AnimationData>? {
        guard let id = selectedAnimationId else { return nil }
        guard animations.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.animations.first(where: { $0.id == id }) ?? AnimationData(name: "") },
            set: { newValue in
                guard let idx = self.animations.firstIndex(where: { $0.id == id }) else { return }
                self.animations[idx] = newValue
                self.save()
            }
        )
    }

    func save() {
        guard let data = try? JSONEncoder().encode(animations) else { return }
        try? data.write(to: saveURL)
        if let id = selectedAnimationId {
            UserDefaults.standard.set(id.uuidString, forKey: "animSelectedId")
        } else {
            UserDefaults.standard.removeObject(forKey: "animSelectedId")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([AnimationData].self, from: data) else { return }
        animations = decoded
        if let idStr = UserDefaults.standard.string(forKey: "animSelectedId"),
           let id = UUID(uuidString: idStr),
           animations.contains(where: { $0.id == id }) {
            selectedAnimationId = id
        } else {
            selectedAnimationId = animations.first?.id
        }
    }
}

private func imageSize(at path: String) -> CGSize? {
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    let rep = image.representations.first
    return CGSize(width: rep?.pixelsWide ?? Int(image.size.width), height: rep?.pixelsHigh ?? Int(image.size.height))
}

// MARK: - Animation Content View

struct AnimationContentView: View {
    @State private var animName: String = ""
    @ObservedObject private var animStore = AnimationStore.shared
    @ObservedObject private var imageStore = ImageStore.shared
    @AppStorage("animLoop") private var loopEnabled = true
    @AppStorage("animPingPong") private var pingPongEnabled = false
    @AppStorage("animSpeed") private var speedText = "1"
    @State private var selectedFrameIndex = 0
    @State private var frameWidthText: String = ""
    @State private var frameHeightText: String = ""
    @FocusState private var animNameFocused: Bool
    @FocusState private var previewFocused: Bool
    @State private var animBgColor: Color = .black
    @State private var transparentBg: Bool = false
    @State private var prevAnimId: UUID?

    private var selectedAnimBinding: Binding<AnimationData>? {
        animStore.selectedAnimationBinding
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("New Anim:").font(.headline)
                TextField("", text: $animName).textFieldStyle(.roundedBorder)
                    .focused($animNameFocused)
                    .onSubmit { animNameFocused = false; animStore.add(name: animName); animName = "" }
                Button(action: { animNameFocused = false; animStore.add(name: animName); animName = "" }) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(animName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal).padding(.top, 8)

            HStack(spacing: 10) {
                Toggle("Loop", isOn: $loopEnabled).toggleStyle(.checkbox).font(.caption)
                Toggle("Ping-pong", isOn: $pingPongEnabled).toggleStyle(.checkbox).font(.caption)
                Text("Speed:").font(.caption).foregroundColor(.secondary)
                TextField("", text: $speedText).textFieldStyle(.roundedBorder).frame(width: 40)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 2)

            if let _ = animStore.selectedAnimation {
                HStack(spacing: 8) {
                    Text("W:").font(.caption).foregroundColor(.secondary)
                    TextField("px", text: $frameWidthText)
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                        .onSubmit { applyFrameSize() }
                    Text("H:").font(.caption).foregroundColor(.secondary)
                    TextField("px", text: $frameHeightText)
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                        .onSubmit { applyFrameSize() }
                    ColorPicker("Bg", selection: $animBgColor).frame(width: 30)
                    Spacer()
                    Toggle("Transparent", isOn: $transparentBg).toggleStyle(.checkbox).font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
            }

            VStack(spacing: 2) {
                HStack {
                    Text("Preview").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    animNameFocused = false
                    previewFocused = true
                }

                AnimPreview(animStore: animStore, imageStore: imageStore, loopEnabled: $loopEnabled, pingPongEnabled: $pingPongEnabled, speedText: $speedText, selectedFrameIndex: $selectedFrameIndex)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            .focusable()
            .focused($previewFocused)

            List(animStore.animations, selection: $animStore.selectedAnimationId) { anim in
                HStack {
                    Text(anim.name).font(.body)
                    Spacer()
                    Button(role: .destructive) {
                        animStore.remove(anim.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .tag(anim.id)
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 4) {
                Text(animStore.selectedAnimation?.name ?? "No anim selected").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, 4)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    if let anim = animStore.selectedAnimation {
                        ForEach(Array(anim.imagePaths.enumerated()), id: \.element) { index, path in
                            if let nsImage = loadThumbnail(path: path) {
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        selectedFrameIndex = index
                                    } label: {
                                        Group {
                                            if anim.frameWidth > 0, anim.frameHeight > 0, index == selectedFrameIndex {
                                                let w = anim.frameWidth
                                                let h = anim.frameHeight
                                                let ox = anim.offsetX.truncatingRemainder(dividingBy: w)
                                                let oy = anim.offsetY.truncatingRemainder(dividingBy: h)
                                                let wx = ox >= 0 ? ox : ox + w
                                                let wy = oy >= 0 ? oy : oy + h
                                                let tile = { Image(nsImage: nsImage).resizable().frame(width: w, height: h) }
                                                let scale = 50 / max(w, h) / 2
                                                ZStack {
                                                    tile().offset(x: wx, y: wy)
                                                    tile().offset(x: wx - w, y: wy)
                                                    tile().offset(x: wx, y: wy - h)
                                                    tile().offset(x: wx - w, y: wy - h)
                                                }
                                                .frame(width: w, height: h)
                                                .clipped()
                                                .scaleEffect(scale)
                                            } else {
                                                Image(nsImage: nsImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            }
                                        }
                                        .frame(width: 50, height: 50)
                                        .contentShape(Rectangle())
                                        .clipped().cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(index == selectedFrameIndex ? Color.accentColor : Color.clear, lineWidth: 3))

                                    Text("\(index + 1)")
                                        .font(.caption2).foregroundColor(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(3)
                                        .offset(x: 3, y: 3)

                                    Button(action: { removeFrame(at: path, from: anim.id) }) {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.white)
                                            .background(Circle().fill(Color.red).frame(width: 10, height: 10))
                                    }
                                    .buttonStyle(.plain).offset(x: 2, y: -2)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 70)
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        .background(animKeyboardButtons)
        .onChange(of: animStore.selectedAnimationId) { newId in
            if let prev = prevAnimId, prev != newId {
                saveBgColor(for: prev)
            }
            prevAnimId = newId
            syncFrameSizeText()
            selectedFrameIndex = 0
            if let anim = animStore.selectedAnimation {
                animBgColor = Color(hex: anim.bgColorHex) ?? .black
                transparentBg = anim.transparentBg
            }
        }
        .onChange(of: animBgColor) { _ in saveBgColor() }
        .onChange(of: transparentBg) { _ in
            guard let id = animStore.selectedAnimationId, let idx = animStore.animations.firstIndex(where: { $0.id == id }) else { return }
            animStore.animations[idx].transparentBg = transparentBg
            animStore.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in saveBgColor() }
        .onAppear {
            syncFrameSizeText()
            if let anim = animStore.selectedAnimation {
                animBgColor = Color(hex: anim.bgColorHex) ?? .black
                transparentBg = anim.transparentBg
            }
            DispatchQueue.main.async { animNameFocused = false }
        }
    }

    private func saveBgColor(for animId: UUID? = nil) {
        let id = animId ?? animStore.selectedAnimationId
        guard let id = id, let idx = animStore.animations.firstIndex(where: { $0.id == id }) else { return }
        animStore.animations[idx].bgColorHex = animBgColor.toHex()
        animStore.save()
    }

    private func syncFrameSizeText() {
        if let anim = animStore.selectedAnimation {
            frameWidthText = anim.frameWidth > 0 ? "\(Int(anim.frameWidth))" : ""
            frameHeightText = anim.frameHeight > 0 ? "\(Int(anim.frameHeight))" : ""
        } else {
            frameWidthText = ""
            frameHeightText = ""
        }
    }

    private func applyFrameSize() {
        guard let binding = selectedAnimBinding else { return }
        let w = max(1, Int(frameWidthText) ?? Int(binding.wrappedValue.frameWidth))
        let h = max(1, Int(frameHeightText) ?? Int(binding.wrappedValue.frameHeight))
        binding.wrappedValue.frameWidth = CGFloat(w)
        binding.wrappedValue.frameHeight = CGFloat(h)
        animStore.save()
        syncFrameSizeText()
    }

    @ViewBuilder
    private var animKeyboardButtons: some View {
        HStack(spacing: 0) {
            Button("") { previousFrame() }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { nextFrame() }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { previousAnimation() }.keyboardShortcut(.upArrow, modifiers: []).opacity(0)
            Button("") { nextAnimation() }.keyboardShortcut(.downArrow, modifiers: []).opacity(0)
            Button("") { nudgeOffset(dx: -1, dy: 0, step: 1) }.keyboardShortcut("j", modifiers: []).opacity(0)
            Button("") { nudgeOffset(dx: 1, dy: 0, step: 1) }.keyboardShortcut("l", modifiers: []).opacity(0)
            Button("") { nudgeOffset(dx: 0, dy: -1, step: 1) }.keyboardShortcut("i", modifiers: []).opacity(0)
            Button("") { nudgeOffset(dx: 0, dy: 1, step: 1) }.keyboardShortcut("k", modifiers: []).opacity(0)
            Button("") { nudgeOffset(dx: -1, dy: 0, step: 10) }.keyboardShortcut("j", modifiers: [.shift]).opacity(0)
            Button("") { nudgeOffset(dx: 1, dy: 0, step: 10) }.keyboardShortcut("l", modifiers: [.shift]).opacity(0)
            Button("") { nudgeOffset(dx: 0, dy: -1, step: 10) }.keyboardShortcut("i", modifiers: [.shift]).opacity(0)
            Button("") { nudgeOffset(dx: 0, dy: 1, step: 10) }.keyboardShortcut("k", modifiers: [.shift]).opacity(0)
            Button("") { animNameFocused = false }.keyboardShortcut(.escape, modifiers: []).opacity(0)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    private func previousFrame() {
        guard let anim = animStore.selectedAnimation, !anim.imagePaths.isEmpty else { return }
        selectedFrameIndex = (selectedFrameIndex - 1 + anim.imagePaths.count) % anim.imagePaths.count
    }

    private func nextFrame() {
        guard let anim = animStore.selectedAnimation, !anim.imagePaths.isEmpty else { return }
        selectedFrameIndex = (selectedFrameIndex + 1) % anim.imagePaths.count
    }

    private func previousAnimation() {
        guard !animStore.animations.isEmpty else { return }
        saveBgColor()
        let ids = animStore.animations.map(\.id)
        if let current = animStore.selectedAnimationId, let idx = ids.firstIndex(of: current) {
            animStore.selectedAnimationId = ids[(idx - 1 + ids.count) % ids.count]
        } else {
            animStore.selectedAnimationId = ids[0]
        }
    }

    private func nextAnimation() {
        guard !animStore.animations.isEmpty else { return }
        saveBgColor()
        let ids = animStore.animations.map(\.id)
        if let current = animStore.selectedAnimationId, let idx = ids.firstIndex(of: current) {
            animStore.selectedAnimationId = ids[(idx + 1) % ids.count]
        } else {
            animStore.selectedAnimationId = ids[0]
        }
    }

    private func nudgeOffset(dx: CGFloat, dy: CGFloat, step: CGFloat = 1) {
        guard let binding = selectedAnimBinding else { return }
        binding.wrappedValue.offsetX += dx * step
        binding.wrappedValue.offsetY += dy * step
        animStore.save()
    }

    private func removeFrame(at path: String, from animationId: UUID) {
        let anim = animStore.animations.first(where: { $0.id == animationId })
        let oldCount = anim?.imagePaths.count ?? 0
        animStore.removeImage(path, from: animationId)
        selectedFrameIndex = min(selectedFrameIndex, max(0, oldCount - 2))
    }

    private func loadThumbnail(path: String) -> NSImage? {
        if let item = imageStore.getItemByPath(path) {
            return item.thumbnail ?? item.image
        }
        return NSImage(contentsOfFile: path)
    }
}

struct AnimPreview: View {
    @ObservedObject var animStore: AnimationStore
    @ObservedObject var imageStore: ImageStore
    @Binding var loopEnabled: Bool
    @Binding var pingPongEnabled: Bool
    @Binding var speedText: String
    @Binding var selectedFrameIndex: Int
    @State private var isPlaying = false
    @State private var direction = 1
    @State private var accumulator: TimeInterval = 0
    @State private var zoomLevel: CGFloat = 1
    @State private var lastZoomLevel: CGFloat = 1
    @State private var lastTilingHash: Int = 0
    @State private var tiledToOriginal: [String: String] = [:]

    @AppStorage("animPreviewHeight") private var previewHeightDouble: Double = 120
    @GestureState private var dragOffset: CGFloat = 0
    private var displayHeight: CGFloat { max(60, min(500, CGFloat(previewHeightDouble) + dragOffset)) }
    private let baseInterval: TimeInterval = 0.08
    @State private var timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    private var parsedSpeed: Double {
        max(0.1, Double(speedText) ?? 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let anim = animStore.selectedAnimation, !anim.imagePaths.isEmpty {
                let paths = anim.imagePaths
                let clampedIndex = min(selectedFrameIndex, paths.count - 1)
                let path = paths[clampedIndex]
                let bgColor = Color(hex: anim.bgColorHex) ?? .black
                if let nsImage = loadImage(path: path) {
                    let useWidth = anim.frameWidth > 0 ? anim.frameWidth : nil
                    let useHeight = anim.frameHeight > 0 ? anim.frameHeight : nil
                    let displayImage = makeDisplayImage(nsImage, path: path, w: useWidth, h: useHeight, offsetX: anim.offsetX, offsetY: anim.offsetY)
                    Image(nsImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomLevel)
                        .frame(maxWidth: .infinity)
                        .background(bgColor)
                        .cornerRadius(6)
                        .frame(height: displayHeight)
                        .contentShape(Rectangle())
                        .clipped()
                        .offset(x: 0, y: 0)
                        .gesture(MagnificationGesture()
                            .onChanged { zoomLevel = max(0.5, min(10, lastZoomLevel * $0)) }
                            .onEnded { _ in lastZoomLevel = zoomLevel })
                        .onReceive(timer) { _ in tick(count: paths.count) }
                }

                Color.gray.opacity(0.2)
                    .frame(height: 4)
                    .cornerRadius(2)
                    .overlay(Rectangle().fill(Color.clear).contentShape(Rectangle()))
                    .gesture(DragGesture()
                        .updating($dragOffset) { value, state, _ in state = value.translation.height }
                        .onEnded { previewHeightDouble = Double(max(60, min(500, CGFloat(previewHeightDouble) + $0.translation.height))) })

                HStack(spacing: 8) {
                    Button(action: togglePlay) {
                        Text(isPlaying ? "Stop" : "Play").font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Stitch") { stitchAndShow() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .frame(height: displayHeight)
                    .overlay(Text("No sprites").foregroundColor(.secondary).font(.caption))
            }
        }
        .onChange(of: animStore.selectedAnimationId) { _ in
            isPlaying = false
            selectedFrameIndex = 0
            direction = 1
            accumulator = 0
            zoomLevel = 1
            lastZoomLevel = 1
            lastTilingHash = 0
            tiledToOriginal = [:]
        }
    }

    private func tick(count: Int) {
        guard isPlaying, count > 0 else { return }
        accumulator += baseInterval
        let frameDuration = baseInterval / parsedSpeed
        while accumulator >= frameDuration {
            accumulator -= frameDuration
            advanceFrame(count: count)
        }
    }

    private func advanceFrame(count: Int) {
        if pingPongEnabled {
            let next = selectedFrameIndex + direction
            if next < 0 || next >= count {
                direction *= -1
                selectedFrameIndex += direction
            } else {
                selectedFrameIndex = next
            }
        } else {
            let next = selectedFrameIndex + 1
            if next >= count {
                if loopEnabled {
                    selectedFrameIndex = 0
                } else {
                    isPlaying = false
                    selectedFrameIndex = count - 1
                }
            } else {
                selectedFrameIndex = next
            }
        }
    }

    private func stitchAndShow() {
        guard let anim = animStore.selectedAnimation, !anim.imagePaths.isEmpty else { return }
        guard let stripe = stripeImage() else { return }
        StripePanelController(stripeImage: stripe).showWindow(nil)
    }

    private func stripeImage() -> NSImage? {
        guard let anim = animStore.selectedAnimation else { return nil }
        let images: [NSImage] = anim.imagePaths.compactMap { path in
            if let item = imageStore.getItemByPath(path) { return item.image }
            return NSImage(contentsOfFile: path)
        }
        guard !images.isEmpty else { return nil }
        let w = anim.frameWidth
        let h = anim.frameHeight
        if w > 0, h > 0 {
            let ox = anim.offsetX.truncatingRemainder(dividingBy: w)
            let oy = anim.offsetY.truncatingRemainder(dividingBy: h)
            let wx = ox >= 0 ? ox : ox + w
            let wy = oy >= 0 ? oy : oy + h
            let totalSize = NSSize(width: w * CGFloat(images.count), height: h)
            let result = NSImage(size: totalSize)
            result.lockFocus()
            if !anim.transparentBg, let ctx = NSGraphicsContext.current?.cgContext {
                let hex = anim.bgColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                var int: UInt64 = 0
                Scanner(string: hex).scanHexInt64(&int)
                let r = CGFloat((int >> 16) & 0xFF) / 255
                let g = CGFloat((int >> 8) & 0xFF) / 255
                let b = CGFloat(int & 0xFF) / 255
                ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
                ctx.fill(NSRect(origin: .zero, size: totalSize))
            }
            for (i, img) in images.enumerated() {
                let x = CGFloat(i) * w
                img.draw(in: NSRect(x: x + wx, y: -wy, width: w, height: h),
                         from: NSRect(origin: .zero, size: img.size),
                         operation: .sourceOver, fraction: 1)
            }
            result.unlockFocus()
            return result
        } else {
            let totalW = images.reduce(0) { $0 + Int($1.size.width) }
            let maxH = images.reduce(0) { max($0, Int($1.size.height)) }
            let result = NSImage(size: NSSize(width: totalW, height: maxH))
            result.lockFocus()
            var x: CGFloat = 0
            for img in images {
                img.draw(in: NSRect(x: x, y: 0, width: img.size.width, height: img.size.height))
                x += img.size.width
            }
            result.unlockFocus()
            return result
        }
    }

    private func togglePlay() {
        if isPlaying {
            isPlaying = false
            selectedFrameIndex = 0
            direction = 1
            accumulator = 0
        } else {
            selectedFrameIndex = 0
            direction = 1
            accumulator = 0
            isPlaying = true
        }
    }

    private func makeDisplayImage(_ image: NSImage, path: String, w: CGFloat?, h: CGFloat?, offsetX: CGFloat, offsetY: CGFloat) -> NSImage {
        guard let w = w, let h = h, !isPlaying else { return image }
        let originalPath = tiledToOriginal[path] ?? path
        let hash = (originalPath + "\(offsetX),\(offsetY),\(w),\(h)").hashValue
        if hash == lastTilingHash { return image }
        lastTilingHash = hash
        guard let srcImage = loadImage(path: originalPath) else { return image }
        let tiled = tiledImage(srcImage, w: w, h: h, offsetX: offsetX, offsetY: offsetY) ?? srcImage
        applyTiledImage(tiled, currentPath: path, originalPath: originalPath)
        return tiled
    }

    private func tiledImage(_ image: NSImage, w: CGFloat, h: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> NSImage? {
        let ox = offsetX.truncatingRemainder(dividingBy: w)
        let oy = offsetY.truncatingRemainder(dividingBy: h)
        let wx = ox >= 0 ? ox : ox + w
        let wy = oy >= 0 ? oy : oy + h
        let result = NSImage(size: NSSize(width: w, height: h))
        result.lockFocus()
        let rects = [
            NSRect(x: wx, y: -wy, width: w, height: h),
            NSRect(x: wx - w, y: -wy, width: w, height: h),
            NSRect(x: wx, y: -wy + h, width: w, height: h),
            NSRect(x: wx - w, y: -wy + h, width: w, height: h),
        ]
        for rect in rects {
            image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        }
        result.unlockFocus()
        return result
    }

    private func applyTiledImage(_ image: NSImage, currentPath: String, originalPath: String) {
        let spritesDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ImageViewer").appendingPathComponent("Sprites")
        try? FileManager.default.createDirectory(at: spritesDir, withIntermediateDirectories: true)
        let url = spritesDir.appendingPathComponent("tiled-\(UUID().uuidString).png")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)

        guard let animId = animStore.selectedAnimationId,
              let animIdx = animStore.animations.firstIndex(where: { $0.id == animId }),
              let pathIdx = animStore.animations[animIdx].imagePaths.firstIndex(of: currentPath) else { return }
        let oldPath = animStore.animations[animIdx].imagePaths[pathIdx]
        if oldPath.contains("/tiled-") { try? FileManager.default.removeItem(atPath: oldPath) }
        animStore.animations[animIdx].imagePaths[pathIdx] = url.path
        tiledToOriginal[url.path] = originalPath
        animStore.save()
    }

    private func loadImage(path: String) -> NSImage? {
        if let item = imageStore.getItemByPath(path) {
            return item.image
        }
        return NSImage(contentsOfFile: path)
    }
}
