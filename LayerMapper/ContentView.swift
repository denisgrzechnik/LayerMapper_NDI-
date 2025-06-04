import SwiftUI
import ReplayKit

// MARK: – Broadcast helper (bez zmian)
final class BroadcastStarter {
    static let shared = BroadcastStarter()
    private let picker = RPSystemBroadcastPickerView(frame: .zero)
    private init() {
        picker.preferredExtension   = "com.layermapper.mobile.screenbroadcast"
        picker.showsMicrophoneButton = false
        picker.isHidden              = true
        UIApplication.shared.windows.first?.addSubview(picker)
    }
    func start() {
        (picker.subviews.first { $0 is UIButton } as? UIButton)?
            .sendActions(for: .touchUpInside)
    }
}

// MARK: – Main view
struct ContentView: View {
    @State private var showPicker    = false
    @State private var pendingIndex  : Int? = nil
    @State private var selectedIndex : Int? = nil

    var body: some View {
        GeometryReader { geo in       // ← detekcja orientacji
            let isLandscape = geo.size.width > geo.size.height
            let bgName      = isLandscape ? "StartBackground"
                                          : "StartBackground_pion"

            ZStack {
                Image(bgName)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Broadcast – kolor #F9154D
                    Button { BroadcastStarter.shared.start() } label: {
                        Label("Broadcast",
                              systemImage: "dot.radiowaves.left.and.right")
                            .broadcastButton()
                    }

                    // Monitor – pół-transparentny biały jak wcześniej
                    Button { showPicker = true } label: {
                        Label("Monitor", systemImage: "eye")
                            .secondaryButton()
                    }
                }

                Button(action: {
                    if let url = URL(string: "https://www.layermapper.com") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }) {
                    Color.clear
                       // .border(Color.red, width: 2) // <-- obramowanie widoczne
                }
                .frame(
                    width: isLandscape ? geo.size.width * 0.5 : geo.size.width * 0.6,
                    height: isLandscape ? 280 : 300
                )
                .position(
                    x: geo.size.width / 2,
                    y: isLandscape
                        ? (geo.size.height - 80 - 50)
                        : (geo.size.height - 150 - 75)
                )
            }
            // 1️⃣ lista źródeł
            .sheet(isPresented: $showPicker,
                   onDismiss: {
                        selectedIndex = pendingIndex
                        pendingIndex  = nil
                   }) {
                SourcePickerView { idx in
                    pendingIndex = idx
                    showPicker   = false
                }
            }
            // 2️⃣ pełnoekranowy monitor
            .fullScreenCover(item: $selectedIndex) { idx in
                MonitorView(sourceIndex: idx)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: – styles
private extension View {

    /// Broadcast – #F9154D
    func broadcastButton() -> some View {
        self.font(.headline.bold())
            .padding(.horizontal, 48).padding(.vertical, 16)
            .background(Color(red: 249/255, green: 21/255, blue: 77/255))
            .foregroundColor(.white)
            .cornerRadius(14)
    }

    /// Monitor – półprzezroczysty biały
    func secondaryButton() -> some View {
        self.font(.headline.bold())
            .padding(.horizontal, 48).padding(.vertical, 16)
            .background(Color.white.opacity(0.25))
            .foregroundColor(.white)
            .cornerRadius(14)
    }
}

// potrzebne do fullScreenCover(item:)
extension Int: Identifiable { public var id: Int { self } }
