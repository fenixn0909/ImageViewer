import AppKit
import SwiftUI

// MARK: - Stripe Window

final class StripePanelController: NSWindowController {
    private static var current: StripePanelController?
    private var monitor: Any?

    private let stripeImage: NSImage

    init(stripeImage: NSImage) {
        Self.current?.window?.close()
        Self.current = nil
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
        Self.current = self
        win.center()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isVisible == true else { return event }
            if event.keyCode == 53 {
                self.window?.close()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                copyStripeToPasteboard(self.stripeImage)
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
    }

    private func copyImage() {
        copyStripeToPasteboard(image)
    }
}

fileprivate func copyStripeToPasteboard(_ image: NSImage) {
    let pb = NSPasteboard.general
    pb.clearContents()

    let w = Int(image.size.width)
    let h = Int(image.size.height)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(h))
    ctx.concatenate(flip)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    guard let cgImage = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
    pb.setData(pngData, forType: .png)
}
