import SwiftUI

struct FileInfoBar: View {
    let item: ImageItem?
    let zoomPercent: Int?

    var body: some View {
        HStack {
            if let item = item {
                Text(fileName).font(.system(size: 11))
                Divider().frame(height: 12)
                Text("\(Int(item.image.size.width)) \u{00D7} \(Int(item.image.size.height)) px").font(.system(size: 11))
                Divider().frame(height: 12)
                Text(fileSize).font(.system(size: 11))

                if !item.filePath.hasPrefix("clipboard") && !item.filePath.hasPrefix("dropped") {
                    Divider().frame(height: 12)
                    Text(item.filePath).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()
                if let zoomPercent = zoomPercent {
                    Divider().frame(height: 12)
                    Text("\(zoomPercent)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4).background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .top)
    }

    var fileSize: String {
        guard let item = item else { return "" }
        if item.filePath.hasPrefix("clipboard") || item.filePath.hasPrefix("dropped") { return "Unknown" }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: item.filePath),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileName: String {
        guard let item = item else { return "" }
        return item.filePath.hasPrefix("clipboard") || item.filePath.hasPrefix("dropped") ? "(Clipboard/Pasted)" : URL(fileURLWithPath: item.filePath).lastPathComponent
    }
}
