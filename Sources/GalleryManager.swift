import SwiftUI

@MainActor
class GalleryManager: ObservableObject {
    static let shared = GalleryManager()

    @Published var galleries: [ImageStore] = []
    @Published var selectedTab: Int = 0

    var activeStore: ImageStore {
        selectedTab == 0 ? galleries[0] : galleries[selectedTab - 1]
    }
    var canAdd: Bool { galleries.count < 3 }
    var canRemove: Bool { galleries.count > 1 }

    private init() {
        galleries.append(ImageStore.shared)
        for i in 2...3 {
            let name = "g\(i)"
            let url = pathsURL(name: name)
            if FileManager.default.fileExists(atPath: url.path) {
                galleries.append(ImageStore(persistentName: name))
            }
        }
    }

    private var appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ImageViewer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func pathsURL(name: String) -> URL {
        appSupportDir.appendingPathComponent("paths-\(name).json")
    }

    func addGallery() {
        guard canAdd else { return }
        let name = "g\(galleries.count + 1)"
        galleries.append(ImageStore(persistentName: name))
        selectedTab = galleries.count
    }

    func removeLastGallery() {
        guard canRemove else { return }
        let name = "g\(galleries.count)"
        let url = pathsURL(name: name)
        try? FileManager.default.removeItem(at: url)
        galleries.removeLast()
        if selectedTab > galleries.count {
            selectedTab = galleries.count
        }
    }

    func galleryName(at index: Int) -> String {
        "Gallery\(index + 1)"
    }
}
