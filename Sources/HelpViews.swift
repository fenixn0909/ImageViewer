import AppKit
import SwiftUI

// MARK: - Shortcuts Window

final class ShortcutsWindowController: NSWindowController {
    static let shared = ShortcutsWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Keyboard Shortcuts"
        win.level = .normal
        win.hidesOnDeactivate = false
        win.minSize = NSSize(width: 400, height: 400)
        let hostingView = NSHostingView(rootView: ShortcutsView())
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView
        super.init(window: win)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }
}

struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Global") {
                    row("Cmd+O", "Open files/folders")
                    row("Cmd+V", "Paste image from clipboard")
                    row("Cmd+W", "Close window")
                    row("Cmd+A", "Select all")
                    row("Cmd+D", "Deselect")
                    row("Cmd+C", "Copy selection to clipboard (PNG)")
                    row("Cmd+,", "Preferences")
                }
                section("Image Preview") {
                    row("← / →", "Previous / next image")
                    row("↑ / ↓", "Zoom in / out")
                    row("F", "Toggle fixed-size selection")
                    row("G", "Toggle grid overlay")
                    row("S", "Add sprite from selection to sequence")
                    row("Cmd+E", "Export selection as PNG")
                    row("Escape", "Defocus text fields / cancel")
                }
                section("File Browser") {
                    row("Click", "Select file / enter directory")
                    row("Cmd+click", "Toggle multi-selection")
                    row("Shift+click", "Range selection")
                    row("Right-click", "Context menu → Add To Gallery")
                }
                section("Animation / Sequence") {
                    row("Enter / Space", "Play / pause")
                    row("← / →", "Previous / next frame")
                    row("↑ / ↓", "Previous / next sequence")
                    row("J / L", "Nudge offset left / right (1px)")
                    row("I / K", "Nudge offset up / down (1px)")
                    row("Shift+J/K/L/I", "Nudge by 10px")
                    row("M", "Merge frames → Stripe window")
                    row("A", "Close animation window, focus main")
                }
                section("Stripe Window") {
                    row("Escape", "Close")
                    row("Cmd+C", "Copy stripe image as PNG")
                }
                section("Convert Area (ATA)") {
                    row("Q", "Open Convert Area panel")
                    row("Enter", "Confirm and create sequence")
                    row("Escape", "Close panel")
                }
                section("Pave Compositing Board") {
                    row("P", "Toggle Pave panel")
                    row("Cmd+V", "Paste image as floating")
                    row("Enter", "Commit floating image to layer")
                    row("Escape", "Cancel floating image")
                    row("Cmd+R", "Rotate floating image 90° CW")
                    row("Cmd+Shift+R", "Rotate floating image 90° CCW")
                    row("Cmd+F", "Flip floating image horizontally")
                    row("Cmd+Shift+F", "Flip floating image vertically")
                    row("Cmd+G", "Toggle grid overlay")
                    row("Cmd+C", "Copy selection area to clipboard")
                    row("Cmd+D", "Clear selection")
                    row("Cmd+Z", "Undo")
                    row("Cmd+Shift+Z", "Redo")
                }
                section("Tab Navigation") {
                    row("Tab", "Cycle through tabs")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).padding(.top, 4)
            Divider()
            content()
        }
    }

    private func row(_ key: String, _ action: String) -> some View {
        HStack {
            Text(key).font(.system(.caption, design: .monospaced)).frame(width: 160, alignment: .trailing)
            Text(action).font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Features Window

final class FeaturesWindowController: NSWindowController {
    static let shared = FeaturesWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "App Features"
        win.level = .normal
        win.hidesOnDeactivate = false
        win.minSize = NSSize(width: 400, height: 400)
        let hostingView = NSHostingView(rootView: FeaturesView())
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView
        super.init(window: win)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }
}

struct FeaturesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Multi-Gallery Tabs") {
                    item("Tabbed sidebar with Browser and up to 3 independent gallery tabs, each with its own image set, selection, and persistence.")
                    item("Add/remove galleries via +/- buttons with confirmation on non-empty removal.")
                    item("Switch tabs with Tab key or click.")
                }
                section("File Browser") {
                    item("Navigate directories with back button and Choose… folder picker.")
                    item("Image-only filtering, sorted directories-first then alphabetically.")
                    item("Multi-selection: click, Cmd+click, Shift+click.")
                    item("Click a file to preview without adding to gallery.")
                    item("Right-click → Add To Gallery context menu.")
                }
                section("Image Preview") {
                    item("Full-resolution display with scroll/pan and zoom (↑/↓, pinch).")
                    item("Drag-to-select with resizable selection rectangle.")
                    item("Fixed-size selection: enable in toolbar, enter W×H, click to place.")
                    item("Grid overlay with configurable color, stroke, cell size, and offset.")
                    item("Snap selection to grid lines.")
                    item("Copy, export (Cmd+E), add sprite to sequence, change selection color.")
                }
                section("Sequence & Animation") {
                    item("Named sequences with ordered image frames, each with per-frame offset.")
                    item("Configurable frame dimensions, background color, transparency.")
                    item("4-tile wrapping preview, playback with loop/ping-pong modes.")
                    item("Merge frames into a horizontal stripe image (PNG).")
                    item("Export individual sequence or export all at once.")
                }
                section("Convert Area to Animation (ATA)") {
                    item("Select an area, choose grid size, extract every grid cell as a separate frame.")
                    item("Creates a new sequence with all extracted frames.")
                }
                section("Pave Compositing Board") {
                    item("Floating panel with up to 5 board tabs.")
                    item("Layers sidebar: add/remove, toggle visibility, rename, reorder.")
                    item("Paste images from clipboard as floating pre-pave images.")
                    item("Commit (Enter) or cancel (Escape) floating images.")
                    item("Rotate (Cmd+R / Cmd+Shift+R) and flip (Cmd+F / Cmd+Shift+F) floating images.")
                    item("Area selection with marching-ants border; copy or clear.")
                    item("Grid overlay with configurable stroke color, width, snap-to-grid.")
                    item("Pinch-to-zoom, two-finger pan when zoomed in.")
                    item("Right-click on grid cell to extract and float the cell content.")
                    item("Undo/Redo per board.")
                    item("Persistence: board metadata + per-layer PNGs saved on quit.")
                }
                section("Preferences") {
                    item("Checkerboard light/dark colors, tile width/height steppers.")
                    item("Show Pave Panel on startup checkbox.")
                }
                section("Drag & Drop") {
                    item("Drop image files or folders onto gallery sidebar.")
                    item("Add To Gallery from browser context menu.")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).padding(.top, 4)
            Divider()
            content()
        }
    }

    private func item(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(.caption)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }
}
