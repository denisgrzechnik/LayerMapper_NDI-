import SwiftUI
import CoreVideo

struct MonitorView: View {

    // --------------------------------------------------
    // MARK: – public
    // --------------------------------------------------
    @Environment(\.presentationMode) private var pres
    let sourceIndex: Int

    // --------------------------------------------------
    // MARK: – state
    // --------------------------------------------------
    @State private var frame        : CVPixelBuffer?
    @State private var receiver     : NDIReceiver?
    @State private var showControls = true            // widoczność „X”
    @State private var hideTask     : DispatchWorkItem?

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

            // ---------- przycisk ----------
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
                .transition(.opacity)                // płynne znikanie
            }
        }
        // ---------- gest tap ----------
        .contentShape(Rectangle())                   // całe ZStack reaguje
        .onTapGesture { showTempControls() }

        // ---------- life-cycle ----------
        .onAppear {
            startReceiver()
            showTempControls()                       // startowe 3 s
        }
        .statusBar(hidden: true)       
        .ignoresSafeArea()
    }

    // --------------------------------------------------
    // MARK: – helpers
    // --------------------------------------------------
    private func startReceiver() {
        receiver = NDIReceiver(sourceIndex: sourceIndex)
        receiver?.onFrame = { pb in
            DispatchQueue.main.async { self.frame = pb }
        }
    }

    /// pokazuje przycisk i ustawia timer, który schowa go po 3 s
    private func showTempControls() {
        withAnimation { showControls = true }

        // anuluj poprzedni timer
        hideTask?.cancel()

        // nowy timer
        let task = DispatchWorkItem {
            withAnimation { showControls = false }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}
