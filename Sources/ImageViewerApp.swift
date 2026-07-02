import AppKit
import SwiftUI

@main
struct ImageViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(GalleryManager.shared)
                .frame(minWidth: 800, minHeight: 400)
                .onAppear {
                    if let window = NSApplication.shared.windows.first {
                        window.minSize = NSSize(width: 400, height: 300)
                        window.title = "Image Viewer"
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Close Window") {
                    if let window = NSApplication.shared.keyWindow {
                        window.close()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    PreferencesWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Select All") {
                    NotificationCenter.default.post(name: .selectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect") {
                    NotificationCenter.default.post(name: .clearSelection, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Copy Selection") {
                    NotificationCenter.default.post(name: .copySelection, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Divider()
                
                Button("Paste Image") {
                    pasteImage()
                }
                .keyboardShortcut("v", modifiers: .command)
                
                Divider()
                
                Button("Clear Gallery") {
                    GalleryManager.shared.activeStore.clearAll()
                }
            }
        }
    }
    
    @MainActor
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .gif, .bmp]

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task {
                    await ImageLoader.shared.loadAndSend(url: url, to: GalleryManager.shared.activeStore)
                }
            }
        }
    }
    
    @MainActor
    private func pasteImage() {
        let pasteboard = NSPasteboard.general
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            for url in fileURLs {
                Task { await ImageLoader.shared.loadAndSend(url: url, to: GalleryManager.shared.activeStore) }
            }
        } else if let image = NSImage(pasteboard: pasteboard) {
            let path = "clipboard-\(UUID().uuidString)"
            GalleryManager.shared.activeStore.addImage(image, thumbnail: nil, path: path)
        }
    }
}

extension Notification.Name {
    static let selectAll = Notification.Name("ImageViewer_SelectAll")
    static let copySelection = Notification.Name("ImageViewer_CopySelection")
    static let applyFixedSize = Notification.Name("ImageViewer_ApplyFixedSize")
    static let clearSelection = Notification.Name("ImageViewer_ClearSelection")
    static let zoomIn = Notification.Name("ImageViewer_ZoomIn")
    static let zoomOut = Notification.Name("ImageViewer_ZoomOut")
}
