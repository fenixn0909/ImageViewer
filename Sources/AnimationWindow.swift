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

struct AnimFrame: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
}

struct AnimationData: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var frames: [AnimFrame] = []
    var frameWidth: CGFloat = 0
    var frameHeight: CGFloat = 0
    var bgColorHex: String = "#000000"
    var transparentBg: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, frames, imagePaths, frameWidth, frameHeight, offsetX, offsetY, bgColorHex, transparentBg
    }

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        frameWidth = try container.decodeIfPresent(CGFloat.self, forKey: .frameWidth) ?? 0
        frameHeight = try container.decodeIfPresent(CGFloat.self, forKey: .frameHeight) ?? 0
        bgColorHex = try container.decodeIfPresent(String.self, forKey: .bgColorHex) ?? "#000000"
        transparentBg = try container.decodeIfPresent(Bool.self, forKey: .transparentBg) ?? false

        if let loadedFrames = try container.decodeIfPresent([AnimFrame].self, forKey: .frames) {
            frames = loadedFrames
        } else if let legacyPaths = try container.decodeIfPresent([String].self, forKey: .imagePaths) {
            let oldOffsetX = try container.decodeIfPresent(CGFloat.self, forKey: .offsetX) ?? 0
            let oldOffsetY = try container.decodeIfPresent(CGFloat.self, forKey: .offsetY) ?? 0
            frames = legacyPaths.map { AnimFrame(path: $0, offsetX: oldOffsetX, offsetY: oldOffsetY) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(frames, forKey: .frames)
        try container.encode(frameWidth, forKey: .frameWidth)
        try container.encode(frameHeight, forKey: .frameHeight)
        try container.encode(bgColorHex, forKey: .bgColorHex)
        try container.encode(transparentBg, forKey: .transparentBg)
    }
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
              !animations[idx].frames.contains(where: { $0.path == path }) else { return }
        let wasEmpty = animations[idx].frames.isEmpty
        animations[idx].frames.append(AnimFrame(path: path))
        if wasEmpty, let size = imageSize(at: path) {
            animations[idx].frameWidth = size.width
            animations[idx].frameHeight = size.height
        }
        save()
    }

    func removeImage(_ path: String, from animationId: UUID) {
        guard let idx = animations.firstIndex(where: { $0.id == animationId }) else { return }
        animations[idx].frames.removeAll { $0.path == path }
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
                        ForEach(Array(anim.frames.enumerated()), id: \.element.id) { index, frame in
                            if let nsImage = loadThumbnail(path: frame.path) {
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        selectedFrameIndex = index
                                    } label: {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
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

                                    Button(action: { removeFrame(at: frame.path, from: anim.id) }) {
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
        .overlay(animKeyboardButtons)
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
            Button("") { defocusAll(); previousFrame() }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { defocusAll(); nextFrame() }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
            Button("") { defocusAll(); previousAnimation() }.keyboardShortcut(.upArrow, modifiers: []).opacity(0)
            Button("") { defocusAll(); nextAnimation() }.keyboardShortcut(.downArrow, modifiers: []).opacity(0)
            Button("") { defocusAll(); nudgeOffset(dx: -1, dy: 0, step: 1) }.keyboardShortcut("j", modifiers: []).opacity(0)
            Button("") { defocusAll(); nudgeOffset(dx: 1, dy: 0, step: 1) }.keyboardShortcut("l", modifiers: []).opacity(0)
            Button("") { defocusAll(); nudgeOffset(dx: 0, dy: -1, step: 1) }.keyboardShortcut("i", modifiers: []).opacity(0)
            Button("") { defocusAll(); nudgeOffset(dx: 0, dy: 1, step: 1) }.keyboardShortcut("k", modifiers: []).opacity(0)
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
        guard let anim = animStore.selectedAnimation, !anim.frames.isEmpty else { return }
        selectedFrameIndex = (selectedFrameIndex - 1 + anim.frames.count) % anim.frames.count
    }

    private func nextFrame() {
        guard let anim = animStore.selectedAnimation, !anim.frames.isEmpty else { return }
        selectedFrameIndex = (selectedFrameIndex + 1) % anim.frames.count
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

    private func defocusAll() {
        animNameFocused = false
        previewFocused = true
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func nudgeOffset(dx: CGFloat, dy: CGFloat, step: CGFloat = 1) {
        guard let binding = selectedAnimBinding else { return }
        guard selectedFrameIndex >= 0 && selectedFrameIndex < binding.wrappedValue.frames.count else { return }
        binding.wrappedValue.frames[selectedFrameIndex].offsetX += dx * step
        binding.wrappedValue.frames[selectedFrameIndex].offsetY += dy * step
        animStore.save()
    }

    private func removeFrame(at path: String, from animationId: UUID) {
        let anim = animStore.animations.first(where: { $0.id == animationId })
        let oldCount = anim?.frames.count ?? 0
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
    @State private var displayCache: [String: NSImage] = [:]

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
            if let anim = animStore.selectedAnimation, !anim.frames.isEmpty {
                let frames = anim.frames
                let clampedIndex = min(selectedFrameIndex, frames.count - 1)
                let frame = frames[clampedIndex]
                let bgColor = Color(hex: anim.bgColorHex) ?? .black
                if let nsImage = loadImage(path: frame.path) {
                    let useWidth = anim.frameWidth > 0 ? anim.frameWidth : nil
                    let useHeight = anim.frameHeight > 0 ? anim.frameHeight : nil
                    let displayImage = makeDisplayImage(nsImage, path: frame.path, w: useWidth, h: useHeight, offsetX: frame.offsetX, offsetY: frame.offsetY)
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
                        .onReceive(timer) { _ in tick(count: frames.count) }
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
            displayCache.removeAll()
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
        guard let anim = animStore.selectedAnimation, !anim.frames.isEmpty else { return }
        guard let stripe = stripeImage() else { return }
        StripePanelController(stripeImage: stripe).showWindow(nil)
    }

    private func stripeImage() -> NSImage? {
        guard let anim = animStore.selectedAnimation else { return nil }
        let frames = anim.frames
        guard !frames.isEmpty else { return nil }

        let w = anim.frameWidth
        let h = anim.frameHeight

        if w > 0, h > 0 {
            let totalSize = NSSize(width: w * CGFloat(frames.count), height: h)
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

            for (i, frame) in frames.enumerated() {
                let img = loadImage(path: frame.path) ?? NSImage(contentsOfFile: frame.path)
                guard let img = img else { continue }

                let xOffset = CGFloat(i) * w
                let ox = frame.offsetX.truncatingRemainder(dividingBy: w)
                let oy = frame.offsetY.truncatingRemainder(dividingBy: h)
                let wx = ox >= 0 ? ox : ox + w
                let wy = oy >= 0 ? oy : oy + h

                let targetRect = NSRect(x: xOffset, y: 0, width: w, height: h)

                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: targetRect).addClip()

                let rects = [
                    NSRect(x: xOffset + wx, y: -wy, width: w, height: h),
                    NSRect(x: xOffset + wx - w, y: -wy, width: w, height: h),
                    NSRect(x: xOffset + wx, y: -wy + h, width: w, height: h),
                    NSRect(x: xOffset + wx - w, y: -wy + h, width: w, height: h),
                ]

                for rect in rects {
                    img.draw(in: rect, from: NSRect(origin: .zero, size: img.size), operation: .sourceOver, fraction: 1)
                }

                NSGraphicsContext.current?.restoreGraphicsState()
            }

            result.unlockFocus()
            return result
        } else {
            let images = frames.compactMap { loadImage(path: $0.path) ?? NSImage(contentsOfFile: $0.path) }
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
        let cacheKey = "\(path)_\(w)_\(h)_\(offsetX)_\(offsetY)"
        if let cached = displayCache[cacheKey] { return cached }
        let tiled = tiledImage(image, w: w, h: h, offsetX: offsetX, offsetY: offsetY) ?? image
        DispatchQueue.main.async {
            if displayCache.count > 50 { displayCache.removeAll() }
            displayCache[cacheKey] = tiled
        }
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

    private func loadImage(path: String) -> NSImage? {
        if let item = imageStore.getItemByPath(path) {
            return item.image
        }
        return NSImage(contentsOfFile: path)
    }
}
