import SwiftUI
import CoreVideo
import QuartzCore

// MARK: - helper: stały zegar prezentacji + mostek do NDIReceiver
final class DisplayLinkProxy {

    private weak var receiver: NDIReceiver?
    private let onFrame: (CVPixelBuffer) -> Void

    private var ready   = false          // czy mamy rozbieg?
    private let warmUp  = 3              // ile klatek przed startem

    init(receiver: NDIReceiver?,
         onFrame: @escaping (CVPixelBuffer) -> Void) {
        self.receiver = receiver
        self.onFrame  = onFrame
    }

    /// wywoływane przez CADisplayLink (na głównym wątku)
    @objc func tick() {
        guard let q = receiver?.queue else { return }

        // 1. rozbieg – czekamy aż w buforze będzie ≥ warmUp klatek
        if !ready {
            ready = q.level >= warmUp
            return
        }

        // 2. normalne odtwarzanie
        if let pb = q.popNext() {
            onFrame(pb)
        } else {
            // 3. underrun – bufor pusty → zrób kolejny rozbieg
            ready = false
        }
    }
}

// MARK: - główny widok monitora
struct MonitorView: View {

    // --------------------------------------------------
    // MARK: – public
    // --------------------------------------------------
    @Environment(\.presentationMode) private var pres
    let sourceIndex: Int

    // --------------------------------------------------
    // MARK: – state
    // --------------------------------------------------
    @State private var frame: CVPixelBuffer?
    @State private var receiver: NDIReceiver?
    @State private var showControls = true
    @State private var hideTask: DispatchWorkItem?
    @State private var displayLink: CADisplayLink?
    @State private var proxy: DisplayLinkProxy?     // <- przechowujemy proxy

    // --------------------------------------------------
    // MARK: – body
    // --------------------------------------------------
    var body: some View {
        ZStack(alignment: .topLeading) {

            // ---------- obraz ----------
            if let pb = frame {
                PixelBufferView(pixelBuffer: pb)
                    .ignoresSafeArea()
            } else {
                ProgressView("Łączenie…")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }

            // ---------- przycisk „X” ----------
            if showControls {
                Button { pres.wrappedValue.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .padding(.top, 30)
                .padding(.leading, 20)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showTempControls() }

        // ---------- life-cycle ----------
        .onAppear { onAppearActions() }
        .onDisappear { onDisappearActions() }

        .statusBar(hidden: true)
        .ignoresSafeArea()
    }

    // --------------------------------------------------
    // MARK: – helpers
    // --------------------------------------------------

    /// konfiguracja przy wejściu na ekran
    private func onAppearActions() {
        startReceiver()
        showTempControls()

        // włącz CADisplayLink dopiero, gdy receiver istnieje
        if let rec = receiver {
            let prox = DisplayLinkProxy(receiver: rec) { pb in
                self.frame = pb
            }
            proxy = prox

            let link = CADisplayLink(target: prox,
                                     selector: #selector(DisplayLinkProxy.tick))
            link.preferredFramesPerSecond = 30    // zmień na 30, jeśli wolisz
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    /// sprzątanie przy wyjściu
    private func onDisappearActions() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
    }

    /// uruchamia odbiornik NDI – bez bezpośredniego callbacku do UI
    private func startReceiver() {
        receiver = NDIReceiver(sourceIndex: sourceIndex)
        // Klasyczny onFrame nie jest już potrzebny – bufor + CADisplayLink
    }

    /// pokazuje przycisk i chowa go po 3 s
    private func showTempControls() {
        withAnimation { showControls = true }

        hideTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation { showControls = false }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}
