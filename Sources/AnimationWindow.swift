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

// MARK: - Sequence Model

struct SeqFrame: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
}

struct SequenceData: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var frames: [SeqFrame] = []
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

        if let loadedFrames = try container.decodeIfPresent([SeqFrame].self, forKey: .frames) {
            frames = loadedFrames
        } else if let legacyPaths = try container.decodeIfPresent([String].self, forKey: .imagePaths) {
            let oldOffsetX = try container.decodeIfPresent(CGFloat.self, forKey: .offsetX) ?? 0
            let oldOffsetY = try container.decodeIfPresent(CGFloat.self, forKey: .offsetY) ?? 0
            frames = legacyPaths.map { SeqFrame(path: $0, offsetX: oldOffsetX, offsetY: oldOffsetY) }
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

// MARK: - Sequence Store

@MainActor
final class SeqStore: ObservableObject {
    static let shared = SeqStore()
    @Published var sequences: [SequenceData] = []
    @Published var selectedSequenceId: UUID?

    private let appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ImageViewer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var saveURL: URL { appSupportDir.appendingPathComponent("sequences.json") }

    private init() { load() }

    func add(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !sequences.contains(where: { $0.name == trimmed }) else { return }
        let _seq = SequenceData(name: trimmed)
        sequences.append(_seq)
        if selectedSequenceId == nil { selectedSequenceId = _seq.id }
        save()
    }

    func remove(_ id: UUID) {
        sequences.removeAll { $0.id == id }
        if selectedSequenceId == id { selectedSequenceId = sequences.first?.id }
        save()
    }

    func addImage(_ path: String) {
        guard let id = selectedSequenceId, let idx = sequences.firstIndex(where: { $0.id == id }),
              !sequences[idx].frames.contains(where: { $0.path == path }) else { return }
        let wasEmpty = sequences[idx].frames.isEmpty
        sequences[idx].frames.append(SeqFrame(path: path))
        if wasEmpty, let size = imageSize(at: path) {
            sequences[idx].frameWidth = size.width
            sequences[idx].frameHeight = size.height
        }
        save()
    }

    func removeImage(_ path: String, from sequenceId: UUID) {
        guard let idx = sequences.firstIndex(where: { $0.id == sequenceId }) else { return }
        sequences[idx].frames.removeAll { $0.path == path }
        save()
    }

    var selectedSequence: SequenceData? {
        guard let id = selectedSequenceId else { return nil }
        return sequences.first { $0.id == id }
    }

    var selectedSequenceIndex: Int? {
        guard let id = selectedSequenceId else { return nil }
        return sequences.firstIndex(where: { $0.id == id })
    }

    var selectedSequenceBinding: Binding<SequenceData>? {
        guard let id = selectedSequenceId else { return nil }
        guard sequences.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.sequences.first(where: { $0.id == id }) ?? SequenceData(name: "") },
            set: { newValue in
                guard let idx = self.sequences.firstIndex(where: { $0.id == id }) else { return }
                self.sequences[idx] = newValue
                self.save()
            }
        )
    }

    func save() {
        guard let data = try? JSONEncoder().encode(sequences) else { return }
        try? data.write(to: saveURL)
        if let id = selectedSequenceId {
            UserDefaults.standard.set(id.uuidString, forKey: "seqSelectedId")
        } else {
            UserDefaults.standard.removeObject(forKey: "seqSelectedId")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([SequenceData].self, from: data) else { return }
        sequences = decoded
        if let idStr = UserDefaults.standard.string(forKey: "seqSelectedId"),
           let id = UUID(uuidString: idStr),
           sequences.contains(where: { $0.id == id }) {
            selectedSequenceId = id
        } else {
            selectedSequenceId = sequences.first?.id
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
    @State private var seqName: String = ""
    @ObservedObject private var seqStore = SeqStore.shared
    @ObservedObject private var imageStore = ImageStore.shared
    @AppStorage("animLoop") private var loopEnabled = true
    @AppStorage("animPingPong") private var pingPongEnabled = false
    @AppStorage("animSpeed") private var speedText = "1"
    @State private var selectedFrameIndex = 0
    @State private var frameWidthText: String = ""
    @State private var frameHeightText: String = ""
    @FocusState private var seqNameFocused: Bool
    @FocusState private var previewFocused: Bool
    @State private var seqBgColor: Color = .black
    @State private var transparentBg: Bool = false
    @State private var prevAnimId: UUID?
    @State private var thumbnailCache: [String: NSImage] = [:]

    private var selectedSeqBinding: Binding<SequenceData>? {
        seqStore.selectedSequenceBinding
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("New Seq:").font(.headline)
                TextField("", text: $seqName).textFieldStyle(.roundedBorder)
                    .focused($seqNameFocused)
                    .onSubmit { seqNameFocused = false; seqStore.add(name: seqName); seqName = "" }
                Button(action: { seqNameFocused = false; seqStore.add(name: seqName); seqName = "" }) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(seqName.trimmingCharacters(in: .whitespaces).isEmpty)
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

            if let _ = seqStore.selectedSequence {
                HStack(spacing: 8) {
                    Text("W:").font(.caption).foregroundColor(.secondary)
                    TextField("px", text: $frameWidthText)
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                        .onSubmit { applyFrameSize() }
                    Text("H:").font(.caption).foregroundColor(.secondary)
                    TextField("px", text: $frameHeightText)
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                        .onSubmit { applyFrameSize() }
                    ColorPicker("Bg", selection: $seqBgColor).frame(width: 30)
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
                    seqNameFocused = false
                    previewFocused = true
                }

                AnimPreview(seqStore: seqStore, imageStore: imageStore, loopEnabled: $loopEnabled, pingPongEnabled: $pingPongEnabled, speedText: $speedText, selectedFrameIndex: $selectedFrameIndex)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            .focusable()
            .focused($previewFocused)

            List(seqStore.sequences, selection: $seqStore.selectedSequenceId) { seq0 in
                HStack {
                    Text(seq0.name).font(.body)
                    Spacer()
                    Button(role: .destructive) {
                        seqStore.remove(seq0.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Rename") { renameSequence(seq0) }
                    Button("Export Seq") { exportSequence(seq0) }
                }
                .tag(seq0.id)
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 4) {
                Text(seqStore.selectedSequence?.name ?? "No seq selected").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, 4)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    if let _seq = seqStore.selectedSequence {
                        ForEach(Array(_seq.frames.enumerated()), id: \.element.id) { index, frame in
                            if let nsImage = loadWrappedThumbnail(frame: frame, w: _seq.frameWidth, h: _seq.frameHeight) {
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

                                    Button(action: { removeFrame(at: frame.path, from: _seq.id) }) {
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
        .onChange(of: seqStore.selectedSequenceId) { newId in
            if let prev = prevAnimId, prev != newId {
                saveBgColor(for: prev)
            }
            prevAnimId = newId
            syncFrameSizeText()
            selectedFrameIndex = 0
            thumbnailCache.removeAll()
            if let _seq = seqStore.selectedSequence {
                seqBgColor = Color(hex: _seq.bgColorHex) ?? .black
                transparentBg = _seq.transparentBg
            }
        }
        .onChange(of: seqBgColor) { _ in saveBgColor() }
        .onChange(of: transparentBg) { _ in
            guard let id = seqStore.selectedSequenceId, let idx = seqStore.sequences.firstIndex(where: { $0.id == id }) else { return }
            seqStore.sequences[idx].transparentBg = transparentBg
            seqStore.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            if let win = notif.object as? NSWindow, win.title == "Animation" {
                previewFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in saveBgColor() }
        .onAppear {
            syncFrameSizeText()
            if let _seq = seqStore.selectedSequence {
                seqBgColor = Color(hex: _seq.bgColorHex) ?? .black
                transparentBg = _seq.transparentBg
            }
            DispatchQueue.main.async { seqNameFocused = false }
        }
    }

    private func saveBgColor(for seqId: UUID? = nil) {
        let id = seqId ?? seqStore.selectedSequenceId
        guard let id = id, let idx = seqStore.sequences.firstIndex(where: { $0.id == id }) else { return }
        seqStore.sequences[idx].bgColorHex = seqBgColor.toHex()
        seqStore.save()
    }

    private func syncFrameSizeText() {
        if let _seq = seqStore.selectedSequence {
            frameWidthText = _seq.frameWidth > 0 ? "\(Int(_seq.frameWidth))" : ""
            frameHeightText = _seq.frameHeight > 0 ? "\(Int(_seq.frameHeight))" : ""
        } else {
            frameWidthText = ""
            frameHeightText = ""
        }
    }

    private func applyFrameSize() {
        guard let binding = selectedSeqBinding else { return }
        let w = max(1, Int(frameWidthText) ?? Int(binding.wrappedValue.frameWidth))
        let h = max(1, Int(frameHeightText) ?? Int(binding.wrappedValue.frameHeight))
        binding.wrappedValue.frameWidth = CGFloat(w)
        binding.wrappedValue.frameHeight = CGFloat(h)
        seqStore.save()
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
            Button("") { seqNameFocused = false }.keyboardShortcut(.escape, modifiers: []).opacity(0)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    private func previousFrame() {
        guard let _seq = seqStore.selectedSequence, !_seq.frames.isEmpty else { return }
        selectedFrameIndex = (selectedFrameIndex - 1 + _seq.frames.count) % _seq.frames.count
    }

    private func nextFrame() {
        guard let _seq = seqStore.selectedSequence, !_seq.frames.isEmpty else { return }
        selectedFrameIndex = (selectedFrameIndex + 1) % _seq.frames.count
    }

    private func previousAnimation() {
        guard !seqStore.sequences.isEmpty else { return }
        saveBgColor()
        let ids = seqStore.sequences.map(\.id)
        if let current = seqStore.selectedSequenceId, let idx = ids.firstIndex(of: current) {
            seqStore.selectedSequenceId = ids[(idx - 1 + ids.count) % ids.count]
        } else {
            seqStore.selectedSequenceId = ids[0]
        }
    }

    private func nextAnimation() {
        guard !seqStore.sequences.isEmpty else { return }
        saveBgColor()
        let ids = seqStore.sequences.map(\.id)
        if let current = seqStore.selectedSequenceId, let idx = ids.firstIndex(of: current) {
            seqStore.selectedSequenceId = ids[(idx + 1) % ids.count]
        } else {
            seqStore.selectedSequenceId = ids[0]
        }
    }

    private func defocusAll() {
        seqNameFocused = false
        previewFocused = true
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func nudgeOffset(dx: CGFloat, dy: CGFloat, step: CGFloat = 1) {
        guard let binding = selectedSeqBinding else { return }
        guard selectedFrameIndex >= 0 && selectedFrameIndex < binding.wrappedValue.frames.count else { return }
        binding.wrappedValue.frames[selectedFrameIndex].offsetX += dx * step
        binding.wrappedValue.frames[selectedFrameIndex].offsetY += dy * step
        seqStore.save()
    }

    private func removeFrame(at path: String, from sequenceId: UUID) {
        let _seq = seqStore.sequences.first(where: { $0.id == sequenceId })
        let oldCount = _seq?.frames.count ?? 0
        seqStore.removeImage(path, from: sequenceId)
        selectedFrameIndex = min(selectedFrameIndex, max(0, oldCount - 2))
    }

    private func renameSequence(_ seq: SequenceData) {
        let alert = NSAlert()
        alert.messageText = "Rename Sequence"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        textField.stringValue = seq.name
        alert.accessoryView = textField
        textField.becomeFirstResponder()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if seqStore.sequences.contains(where: { $0.name == trimmed && $0.id != seq.id }) {
            let ca = NSAlert()
            ca.messageText = "Sequence '\(trimmed)' already exists."
            ca.runModal()
            return
        }
        guard let idx = seqStore.sequences.firstIndex(where: { $0.id == seq.id }) else { return }
        seqStore.sequences[idx].name = trimmed
        seqStore.save()
    }

    private func exportSequence(_ seq: SequenceData) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(seq.name).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let stripe = makeStripeImage(for: seq, imageStore: imageStore) else {
            let alert = NSAlert()
            alert.messageText = "Could not generate merged image."
            alert.runModal()
            return
        }
        guard let tiffData = stripe.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            let alert = NSAlert()
            alert.messageText = "Could not export image."
            alert.runModal()
            return
        }
        try? pngData.write(to: url)
    }

    private func loadThumbnail(path: String) -> NSImage? {
        if let item = imageStore.getItemByPath(path) {
            return item.thumbnail ?? item.image
        }
        return NSImage(contentsOfFile: path)
    }

    private func loadWrappedThumbnail(frame: SeqFrame, w: CGFloat, h: CGFloat) -> NSImage? {
        let rawImage = loadThumbnail(path: frame.path)
        guard let img = rawImage, w > 0, h > 0 else { return rawImage }
        let cacheKey = "\(frame.path)_\(w)_\(h)_\(frame.offsetX)_\(frame.offsetY)_thumb"
        if let cached = thumbnailCache[cacheKey] { return cached }
        let ox = frame.offsetX.truncatingRemainder(dividingBy: w)
        let oy = frame.offsetY.truncatingRemainder(dividingBy: h)
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
            img.draw(in: rect, from: NSRect(origin: .zero, size: img.size), operation: .sourceOver, fraction: 1)
        }
        result.unlockFocus()
        DispatchQueue.main.async {
            if thumbnailCache.count > 50 { thumbnailCache.removeAll() }
            thumbnailCache[cacheKey] = result
        }
        return result
    }
}

struct AnimPreview: View {
    @ObservedObject var seqStore: SeqStore
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
            if let _seq = seqStore.selectedSequence, !_seq.frames.isEmpty {
                let frames = _seq.frames
                let clampedIndex = min(selectedFrameIndex, frames.count - 1)
                let frame = frames[clampedIndex]
                let bgColor = Color(hex: _seq.bgColorHex) ?? .black
                if let nsImage = loadImage(path: frame.path) {
                    let useWidth = _seq.frameWidth > 0 ? _seq.frameWidth : nil
                    let useHeight = _seq.frameHeight > 0 ? _seq.frameHeight : nil
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

                    Button(action: mergeAndShow) {     // btn-merge('m')
                        Image(systemName: "arrow.up.right.and.arrow.down.left.square.fill")
                            .font(.system(size: 14))
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button(action: exportAllSequences) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                    }
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
        .overlay(
            HStack(spacing: 0) {
                Button("") { togglePlay() }.keyboardShortcut(.return, modifiers: [])
                Button("") { togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("") { mergeAndShow() }.keyboardShortcut("m", modifiers: [])
                Button("") {
                    AnimationPanelController.shared.window?.orderOut(nil)
                    if let mainWin = NSApplication.shared.windows.first(where: { $0.title == "Image Viewer" }) {
                        mainWin.makeKeyAndOrderFront(nil)
                    }
                }.keyboardShortcut("a", modifiers: [])
            }
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
        )
        .onChange(of: seqStore.selectedSequenceId) { _ in
            isPlaying = false
            selectedFrameIndex = 0
            direction = 1
            accumulator = 0
            zoomLevel = 1
            lastZoomLevel = 1
            displayCache.removeAll()
        }
    }

    private func exportAllSequences() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export all sequences"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let sequences = seqStore.sequences
        guard !sequences.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No sequences to export."
            alert.runModal()
            return
        }

        var exported = 0
        for seq in sequences {
            let filename = "\(seq.name).png"
            let url = folder.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            guard let stripe = makeStripeImage(for: seq, imageStore: imageStore),
                  let tiffData = stripe.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }
            try? pngData.write(to: url)
            exported += 1
        }

        let alert = NSAlert()
        if exported == 0 {
            alert.messageText = "All sequences already exist in the destination."
        } else {
            alert.messageText = "Exported \(exported) of \(sequences.count) sequences to \(folder.lastPathComponent)."
        }
        alert.runModal()
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

    private func mergeAndShow() {
        guard let _seq = seqStore.selectedSequence, !_seq.frames.isEmpty else { return }
        guard let stripe = stripeImage() else { return }
        StripePanelController(stripeImage: stripe).showWindow(nil)
    }

    private func stripeImage() -> NSImage? {
        guard let _seq = seqStore.selectedSequence else { return nil }
        return makeStripeImage(for: _seq, imageStore: imageStore)
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
        guard let w = w, let h = h else { return image }
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
            image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
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

@MainActor
fileprivate func makeStripeImage(for seq: SequenceData, imageStore: ImageStore) -> NSImage? {
    let frames = seq.frames
    guard !frames.isEmpty else { return nil }

    func loadImg(path: String) -> NSImage? {
        if let item = imageStore.getItemByPath(path) { return item.image }
        return NSImage(contentsOfFile: path)
    }

    let w = seq.frameWidth
    let h = seq.frameHeight

    if w > 0, h > 0 {
        let totalSize = NSSize(width: w * CGFloat(frames.count), height: h)
        let result = NSImage(size: totalSize)
        result.lockFocus()

        if !seq.transparentBg, let ctx = NSGraphicsContext.current?.cgContext {
            let hex = seq.bgColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            let r = CGFloat((int >> 16) & 0xFF) / 255
            let g = CGFloat((int >> 8) & 0xFF) / 255
            let b = CGFloat(int & 0xFF) / 255
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            ctx.fill(NSRect(origin: .zero, size: totalSize))
        }

        for (i, frame) in frames.enumerated() {
            guard let img = loadImg(path: frame.path) else { continue }

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
        let images = frames.compactMap { loadImg(path: $0.path) }
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
