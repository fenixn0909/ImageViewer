import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = "Image Viewer"
        win.contentView = NSHostingView(rootView: contentView)
        win.minSize = NSSize(width: 400, height: 300)
        win.makeKeyAndOrderFront(nil)
        window = win

        setupMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "Load...", action: #selector(openFile), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Copy Selection", action: #selector(copySelection), keyEquivalent: "C")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Paste Image", action: #selector(pasteImage), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Clear All", action: #selector(clearImage), keyEquivalent: "")

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .gif, .bmp]

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task {
                    await ImageLoader.shared.loadAndSend(url: url)
                }
            }
        }
    }

    @objc func pasteImage() {
        let pasteboard = NSPasteboard.general

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            for url in fileURLs {
                Task {
                    await ImageLoader.shared.loadAndSend(url: url)
                }
            }
        } else if let image = NSImage(pasteboard: pasteboard) {
            Task { @MainActor in
                EventBus.shared.pasteImage.send(image)
            }
        }
    }

    @objc func clearImage() {
        EventBus.shared.clearImage.send()
    }

    @objc func copySelection() {
        EventBus.shared.copySelection.send()
    }
}
