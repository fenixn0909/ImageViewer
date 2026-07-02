import SwiftUI

struct SelectionOverlay: View {
    let rect: CGRect
    let selectionColor: Color
    let isFixedSize: Bool
    let onCopy: () -> Void
    let onClear: () -> Void
    let onColorChange: (Color) -> Void
    let onAddSprite: () -> Void
    let onExport: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(selectionColor.opacity(0.2))
            Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4])).foregroundColor(selectionColor)
            
            if !isFixedSize {
                Group {
                    node().position(x: 0, y: 0)
                    node().position(x: rect.width / 2, y: 0)
                    node().position(x: rect.width, y: 0)
                    
                    node().position(x: 0, y: rect.height / 2)
                    node().position(x: rect.width, y: rect.height / 2)
                    
                    node().position(x: 0, y: rect.height)
                    node().position(x: rect.width / 2, y: rect.height)
                    node().position(x: rect.width, y: rect.height)
                }
            }
        }
        .allowsHitTesting(false)
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .overlay(alignment: .bottom) {
            HStack(spacing: 24) {
                Button(action: onCopy) { Image(systemName: "doc.on.doc").font(.system(size: 20)) }
                    .buttonStyle(.plain)
                
                Button(action: onAddSprite) { Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 20)) }
                    .buttonStyle(.plain)
                
                ColorPicker("", selection: Binding(
                    get: { selectionColor },
                    set: { onColorChange($0) }
                ))
                .labelsHidden()
                .frame(width: 16, height: 16)
                
                Button(action: onExport) { Image(systemName: "square.and.arrow.up.fill").font(.system(size: 16)) }
                    .buttonStyle(.plain)
                
                Button(action: onClear) { Image(systemName: "xmark").font(.system(size: 12)) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selectionColor.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(6)
            .fixedSize()
            .offset(y: 48)
        }
        .offset(x: rect.minX, y: rect.minY) 
    }
    
    private func node() -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .border(selectionColor, width: 2)
    }
}
