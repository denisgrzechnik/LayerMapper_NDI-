import SwiftUI

struct SourcePickerView: View {
    var onSelect: (Int) -> Void
    @State private var sources: [String] = []

    private let finder = NDIEnvironment.shared.finder

    var body: some View {
        NavigationView {
            List(sources.indices, id: \.self) { idx in
                Button(sources[idx]) { onSelect(idx) }   // tylko callback
            }
            .navigationTitle("NDI Source")
            .onAppear { startPolling() }
        }
    }

    private func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            var cnt: UInt32 = 0
            if let ptr = NDIlib_find_get_current_sources(finder, &cnt) {
                let buf = UnsafeBufferPointer(start: ptr, count: Int(cnt))
                let names = buf.map { String(cString: $0.p_ndi_name) }
                DispatchQueue.main.async { self.sources = names }
            }
        }.tolerance = 0.2
    }
}

