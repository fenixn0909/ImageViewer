import AppKit
import SwiftUI

// MARK: - Preferences Store

class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var checkerColor1: Color { didSet { save() } }
    @Published var checkerColor2: Color { didSet { save() } }
    @Published var checkerTileWidth: CGFloat { didSet { save() } }
    @Published var checkerTileHeight: CGFloat { didSet { save() } }
    @Published var showPaveOnStartup: Bool { didSet { save() } }

    private init() {
        let h1 = UserDefaults.standard.string(forKey: "checkerColor1") ?? "#FFFFFF"
        let h2 = UserDefaults.standard.string(forKey: "checkerColor2") ?? "#CCCCCC"
        checkerColor1 = Color(hex: h1) ?? .white
        checkerColor2 = Color(hex: h2) ?? .gray.opacity(0.4)
        checkerTileWidth = CGFloat(max(2, UserDefaults.standard.double(forKey: "checkerTileWidth").nonZero ?? 8))
        checkerTileHeight = CGFloat(max(2, UserDefaults.standard.double(forKey: "checkerTileHeight").nonZero ?? 8))
        showPaveOnStartup = UserDefaults.standard.bool(forKey: "showPaveOnStartup")
    }

    private func save() {
        UserDefaults.standard.set(checkerColor1.toHex(), forKey: "checkerColor1")
        UserDefaults.standard.set(checkerColor2.toHex(), forKey: "checkerColor2")
        UserDefaults.standard.set(Double(checkerTileWidth), forKey: "checkerTileWidth")
        UserDefaults.standard.set(Double(checkerTileHeight), forKey: "checkerTileHeight")
        UserDefaults.standard.set(showPaveOnStartup, forKey: "showPaveOnStartup")
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

// MARK: - NSColorWell Representable

private struct ColorWellView: NSViewRepresentable {
    @Binding var color: Color

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = NSColor(color)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = NSColor(color)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ColorWellView
        init(_ parent: ColorWellView) { self.parent = parent }
        @objc func colorChanged(_ sender: NSColorWell) {
            guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
            parent.color = Color(nsColor: srgb)
        }
    }
}

// MARK: - Preferences Window Controller

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Preferences"
        win.level = .normal
        win.hidesOnDeactivate = false
        win.minSize = NSSize(width: 380, height: 240)
        let hostingView = NSHostingView(rootView: PreferencesView())
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

// MARK: - Preferences View

struct PreferencesView: View {
    @State private var selectedItem: PrefItem = .checkerColor

    enum PrefItem: String, CaseIterable {
        case checkerColor = "Checker Color"
    }

    var body: some View {
        NavigationSplitView {
            List(PrefItem.allCases, id: \.self, selection: $selectedItem) { item in
                Text(item.rawValue).tag(item)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140)
        } detail: {
            switch selectedItem {
            case .checkerColor:
                CheckerColorSettingsView()
            }
        }
    }
}

// MARK: - Checker Color Settings

struct CheckerColorSettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Checker Colors").font(.title2).bold()

            HStack(spacing: 48) {
                square(label: "Light Square", color: $prefs.checkerColor1)
                square(label: "Dark Square", color: $prefs.checkerColor2)
            }

            Divider()

            HStack(spacing: 20) {
                HStack {
                    Text("Tile W:").font(.caption).foregroundColor(.secondary)
                    Stepper(value: $prefs.checkerTileWidth, in: 2...128, step: 1) {
                        Text("\(Int(prefs.checkerTileWidth)) px").font(.system(.caption, design: .monospaced))
                    }.frame(width: 130)
                }
                HStack {
                    Text("H:").font(.caption).foregroundColor(.secondary)
                    Stepper(value: $prefs.checkerTileHeight, in: 2...128, step: 1) {
                        Text("\(Int(prefs.checkerTileHeight)) px").font(.system(.caption, design: .monospaced))
                    }.frame(width: 130)
                }
            }

            Toggle("Show Pave Panel on startup", isOn: $prefs.showPaveOnStartup)
                .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func square(label: String, color: Binding<Color>) -> some View {
        VStack(spacing: 8) {
            ColorWellView(color: color)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .gridColor), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}
