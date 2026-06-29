import SwiftUI
import UniformTypeIdentifiers

struct GallerySidebar: View {
    @ObservedObject var store: ImageStore
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.images.isEmpty ? "Gallery" : "Images (\(store.images.count))").font(.headline)
                Spacer()
            }.padding(8).background(Color(nsColor: .controlBackgroundColor))

            if store.images.isEmpty {
                VStack { Spacer(); Text("No images").foregroundColor(.secondary).font(.caption); Spacer() }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(store.images) { item in
                            ThumbnailView(
                                image: item.thumbnail ?? item.image,
                                isSelected: store.selectedImageId == item.id,
                                onRemove: { store.removeImage(item.id) }
                            ).onTapGesture { store.selectedImageId = item.id }
                        }
                    }.padding(8)
                }.frame(maxHeight: .infinity)
            }
            DropAddButton(isTargeted: $isTargeted)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct DropAddButton: View {
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundColor(isTargeted ? .blue : .gray)
            Text("Add").font(.caption2).foregroundColor(isTargeted ? .blue : .secondary)
        }
        .frame(height: 60).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5)))
        .background(RoundedRectangle(cornerRadius: 8).fill(isTargeted ? Color.blue.opacity(0.1) : Color.clear))
        .padding(8).contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url { Task { await ImageLoader.shared.loadAndSend(url: url) } }
                    }
                }
            }
            return true
        }
    }
}

struct ThumbnailView: View {
    let image: NSImage
    let isSelected: Bool
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 50)
                .clipped().cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.white)
                        .background(Circle().fill(Color.red).frame(width: 14, height: 14))
                }.buttonStyle(.plain).offset(x: 4, y: -4)
            }
        }.onHover { isHovered = $0 }
    }
}
