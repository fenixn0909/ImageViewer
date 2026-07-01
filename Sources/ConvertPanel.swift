import AppKit
import SwiftUI

// MARK: - Convert Area to Animation

final class ConvertPanelController: NSWindowController {
    fileprivate static var current: ConvertPanelController?
    private var monitor: Any?

    init() {
        Self.current?.window?.close()
        Self.current = nil
        let hostingView = NSHostingView(rootView: ConvertView())
        hostingView.autoresizingMask = [.width, .height]
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 50),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Convert area to animation"
        win.contentView = hostingView
        super.init(window: win)
        Self.current = self
        win.center()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isVisible == true else { return event }
            if event.keyCode == 53 {
                self.window?.close()
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        window?.makeKeyAndOrderFront(sender)
    }
}

struct ConvertView: View {
    @State private var nameText = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("Sequence Name:")
            TextField("", text: $nameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            Button(action: confirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(nameText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func confirm() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let store = SeqStore.shared
        if store.sequences.contains(where: { $0.name == trimmed }) {
            let alert = NSAlert()
            alert.messageText = "Sequence '\(trimmed)' already exists."
            alert.runModal()
            return
        }

        guard let image = ATAContext.image, let rect = ATAContext.rect else {
            let alert = NSAlert()
            alert.messageText = "No selection area found. Select an area on the image first."
            alert.runModal()
            return
        }

        let settings = SettingsManager.shared
        let gw = settings.parsedGridWidth
        let gh = settings.parsedGridHeight
        guard gw > 0, gh > 0 else {
            let alert = NSAlert()
            alert.messageText = "Grid width and height must be set in the toolbar."
            alert.runModal()
            return
        }

        let cols = Int(rect.width) / gw
        let rows = Int(rect.height) / gh
        guard cols > 0, rows > 0 else {
            let alert = NSAlert()
            alert.messageText = "Selection area is too small for the current grid size (\(gw)\u{00D7}\(gh))."
            alert.runModal()
            return
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let alert = NSAlert()
            alert.messageText = "Could not process image."
            alert.runModal()
            return
        }

        let sX = CGFloat(cgImage.width) / image.size.width
        let sY = CGFloat(cgImage.height) / image.size.height

        let spritesDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ImageViewer").appendingPathComponent("Sprites")
        try? FileManager.default.createDirectory(at: spritesDir, withIntermediateDirectories: true)

        var frames: [SeqFrame] = []

        for row in 0..<rows {
            for col in 0..<cols {
                let x = rect.origin.x + CGFloat(col * gw)
                let y = rect.origin.y + CGFloat(row * gh)
                let pixelRect = CGRect(
                    x: Int((x) * sX),
                    y: Int((y) * sY),
                    width: Int(CGFloat(gw) * sX),
                    height: Int(CGFloat(gh) * sY)
                )
                guard pixelRect.width > 0, pixelRect.height > 0 else { continue }
                guard let chunk = cgImage.cropping(to: pixelRect) else { continue }

                let url = spritesDir.appendingPathComponent("ata-\(UUID().uuidString).png")
                let bitmap = NSBitmapImageRep(cgImage: chunk)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                try? data.write(to: url)

                frames.append(SeqFrame(path: url.path))
            }
        }

        guard !frames.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No frames could be extracted."
            alert.runModal()
            return
        }

        var seq = SequenceData(name: trimmed)
        seq.frames = frames
        seq.frameWidth = CGFloat(gw)
        seq.frameHeight = CGFloat(gh)
        store.sequences.append(seq)
        store.selectedSequenceId = seq.id
        store.save()

        ConvertPanelController.current?.window?.close()

        let alert = NSAlert()
        alert.messageText = "Created sequence '\(trimmed)' with \(frames.count) frames."
        alert.runModal()
    }
}

enum ATAContext {
    static var image: NSImage?
    static var rect: CGRect?
}
