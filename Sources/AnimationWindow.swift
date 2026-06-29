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
}

// MARK: - Animation Store

@MainActor
final class AnimationStore: ObservableObject {
    static let shared = AnimationStore()
    @Published var animations: [AnimationData] = []
    @Published var selectedAnimationId: UUID?

    private var saveURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ImageViewer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("animations.json")
    }

    private init() {}

    func loadSaved() {
        load()
    }

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
        animations[idx].imagePaths.append(path)
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

    private func save() {
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

// MARK: - Animation Content View

struct AnimationContentView: View {
    @State private var animName: String = ""
    @StateObject private var animStore = AnimationStore.shared
    @StateObject private var imageStore = ImageStore.shared
    @State private var loopEnabled = UserDefaults.standard.object(forKey: "animLoop").flatMap { $0 as? Bool } ?? true
    @State private var pingPongEnabled = UserDefaults.standard.bool(forKey: "animPingPong")
    @State private var speedText = UserDefaults.standard.string(forKey: "animSpeed") ?? "1"
    @State private var selectedFrameIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("New Anim:").font(.headline)
                TextField("", text: $animName).textFieldStyle(.roundedBorder)
                Button(action: { animStore.add(name: animName); animName = "" }) {
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

            AnimPreview(animStore: animStore, imageStore: imageStore, loopEnabled: $loopEnabled, pingPongEnabled: $pingPongEnabled, speedText: $speedText, selectedFrameIndex: $selectedFrameIndex)
                .padding(.horizontal, 8).padding(.vertical, 4)

            List(animStore.animations) { anim in
                HStack {
                    Text(anim.name).font(.body)
                    Spacer()
                    Button(action: { animStore.remove(anim.id) }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture { animStore.selectedAnimationId = anim.id }
                .listRowBackground(anim.id == animStore.selectedAnimationId ? Color.accentColor.opacity(0.3) : Color.clear)
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
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipped().cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(index == selectedFrameIndex ? Color.accentColor : Color.clear, lineWidth: 3))
                                        .onTapGesture { selectedFrameIndex = index }

                                    Button(action: { animStore.removeImage(path, from: anim.id) }) {
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in saveViewState() }
    }

    private func saveViewState() {
        UserDefaults.standard.set(loopEnabled, forKey: "animLoop")
        UserDefaults.standard.set(pingPongEnabled, forKey: "animPingPong")
        UserDefaults.standard.set(speedText, forKey: "animSpeed")
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
    @State private var previewHeight: CGFloat = {
        let h = UserDefaults.standard.double(forKey: "animPreviewHeight")
        return h >= 60 ? h : 120
    }()
    @State private var dragStartHeight: CGFloat = 120
    private let baseInterval: TimeInterval = 0.08
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var parsedSpeed: Double {
        max(0.1, Double(speedText) ?? 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let anim = animStore.selectedAnimation, !anim.imagePaths.isEmpty {
                let paths = anim.imagePaths
                let clampedIndex = min(selectedFrameIndex, paths.count - 1)
                let path = paths[clampedIndex]
                if let nsImage = loadImage(path: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomLevel)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(6)
                        .frame(height: previewHeight)
                        .clipped()
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
                        .onChanged { previewHeight = max(60, min(500, dragStartHeight + $0.translation.height)) }
                        .onEnded { _ in dragStartHeight = previewHeight })

                Button(action: togglePlay) {
                    Text(isPlaying ? "Stop" : "Play").font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .frame(height: previewHeight)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            UserDefaults.standard.set(previewHeight, forKey: "animPreviewHeight")
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

    private func loadImage(path: String) -> NSImage? {
        if let item = imageStore.getItemByPath(path) {
            return item.image
        }
        return NSImage(contentsOfFile: path)
    }
}
