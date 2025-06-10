import SwiftUI
import ReplayKit

// MARK: – Broadcast helper (bez zmian)
final class BroadcastStarter {
    static let shared = BroadcastStarter()
    private let picker = RPSystemBroadcastPickerView(frame: .zero)
    private init() {
        picker.preferredExtension    = "com.layermapper.mobile.screenbroadcast"
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
    @State private var pendingIndex  : Int?
    @State private var selectedIndex : Int?

    var body: some View {
        GeometryReader { geo in
            // ——— aktualna orientacja + typ urządzenia
            let isLandscape = geo.size.width > geo.size.height
            let isPhone     = UIDevice.current.userInterfaceIdiom == .phone

            let bgName: String = {
                switch (isPhone, isLandscape) {
                case (true,  true):  return "iphone_poziom"
                case (false, true):  return "ipad_poziom"
                case (true,  false): return "iphone_pion"
                default:             return "ipad_pion"
                }
            }()

            ZStack {
                // Tło
                Image(bgName)
                    .resizable()
                    .scaledToFill()                     // zawsze wypełnia cały ekran
                    .frame(width: geo.size.width,
                           height: geo.size.height)
                    .clipped()
                    .edgesIgnoringSafeArea(.all)

                // Przyciski Broadcast + Monitor
                VStack(spacing: 24) {
                    Button { BroadcastStarter.shared.start() } label: {
                        Label("Broadcast",
                              systemImage: "dot.radiowaves.left.and.right")
                            .broadcastButton()
                    }
                    Button { showPicker = true } label: {
                        Label("Monitor", systemImage: "eye")
                            .secondaryButton()
                    }
                }
                .padding(.horizontal, 20)
            }
            
            .background(Color(red: 29/255, green: 29/255, blue: 29/255))
            .edgesIgnoringSafeArea(.all)
            
            // ——— przezroczysta nakładka „klikalna” (iOS 14 API)
            .overlay(
                Rectangle()                                 // widok umieszczany w nakładce
                    .strokeBorder(Color.red, lineWidth: 0)  // czerwone obramowanie
                    .background(Color.clear)                // pełna przezroczystość
                    .contentShape(Rectangle())              // cały prostokąt ma łapać gesty
                    .frame(
                        width : geo.size.width  * (isPhone ? 0.85 : 0.80),
                        height: geo.size.height * 0.25
                    )
                    .position(
                        x: geo.size.width / 2,
                        y: isPhone && !isLandscape
                            ? geo.size.height * 0.80
                            : geo.size.height * 0.8
                    )
                    .onTapGesture { openWebsite() },        // akcja
                alignment: .center                         // starszy wariant overlay
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()

        // ——— prezentacje modalne (bez zmian)
        .sheet(isPresented: $showPicker, onDismiss: {
            selectedIndex = pendingIndex; pendingIndex = nil
        }) {
            SourcePickerView { idx in
                pendingIndex = idx; showPicker = false
            }
        }
        .fullScreenCover(item: $selectedIndex) { idx in
            MonitorView(sourceIndex: idx).ignoresSafeArea()
        }
    }

    // MARK: – Akcje
    private func openWebsite() {
        guard let url = URL(string: "https://www.layermapper.com") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: – Style przycisków
private extension View {
    /// Broadcast – #F9154D
    func broadcastButton() -> some View {
        self.font(.headline.bold())
            .padding(.horizontal, 48).padding(.vertical, 16)
            .background(Color(red: 249/255, green: 21/255, blue: 77/255))
            .foregroundColor(.white)
            .cornerRadius(14)
    }
    /// Monitor – pół-transparentny biały
    func secondaryButton() -> some View {
        self.font(.headline.bold())
            .padding(.horizontal, 48).padding(.vertical, 16)
            .background(Color.white.opacity(0.25))
            .foregroundColor(.white)
            .cornerRadius(14)
    }
}

// Potrzebne do fullScreenCover(item:)
extension Int: Identifiable { public var id: Int { self } }

