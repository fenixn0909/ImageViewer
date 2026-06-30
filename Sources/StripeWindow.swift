import AppKit
import SwiftUI

// MARK: - Stripe Window

final class StripePanelController: NSWindowController {
    private let stripeImage: NSImage

    init(stripeImage: NSImage) {
        self.stripeImage = stripeImage
        let vw = min(stripeImage.size.width, 800)
        let vh = min(stripeImage.size.height, 600)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: vw, height: vh),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Stripe"
        let hostingView = NSHostingView(rootView: StripeView(image: stripeImage))
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView
        super.init(window: win)
        win.center()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        window?.makeKeyAndOrderFront(sender)
    }
}

struct StripeView: View {
    let image: NSImage

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: copyImage) {
                Image(systemName: "doc.on.doc").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 2))
            .padding(8)
        }
        .background(KeyHandler(image: image))
    }

    private func copyImage() {
        copyToPasteboard(image)
    }
}

private struct KeyHandler: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.nextResponder = context.coordinator
        DispatchQueue.main.async {
            v.window?.makeFirstResponder(v)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class KeyView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image)
    }

    class Coordinator: NSResponder {
        let image: NSImage

        init(image: NSImage) {
            self.image = image
            super.init()
        }

        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                copyImage()
            } else {
                super.keyDown(with: event)
            }
        }

        private func copyImage() {
            copyToPasteboard(image)
        }
    }
}
