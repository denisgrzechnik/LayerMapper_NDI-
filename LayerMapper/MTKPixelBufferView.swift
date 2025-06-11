import SwiftUI
import MetalKit
import CoreImage

struct MTKPixelBufferView: UIViewRepresentable {

    @Binding var pixelBuffer: CVPixelBuffer?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let dev = MTLCreateSystemDefaultDevice()!
        let v   = MTKView(frame: .zero, device: dev)
        v.colorPixelFormat    = .bgra8Unorm
        v.framebufferOnly     = false
        v.autoResizeDrawable  = true
        v.isPaused            = true
        return v
    }

    func updateUIView(_ view: MTKView, context: Context) {
        guard let pb = pixelBuffer else { return }

        // 1. CIImage z bufora
        let ciImage = CIImage(cvPixelBuffer: pb)

        // 2. wymiar drawable = rozmiar obrazka
        view.drawableSize = CGSize(width: ciImage.extent.width,
                                   height: ciImage.extent.height)

        guard let drawable = view.currentDrawable,
              let cmdQ      = context.coordinator.commandQueue,
              let ciCtx     = context.coordinator.ciContext else { return }

        // 3. render CI → drawable.texture w jednym commandBuffer
        let cmdBuf = cmdQ.makeCommandBuffer()!
        ciCtx.render(ciImage,
                     to: drawable.texture,
                     commandBuffer: cmdBuf,
                     bounds: ciImage.extent,
                     colorSpace: CGColorSpaceCreateDeviceRGB())
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: – helper
    final class Coordinator {
        var commandQueue: MTLCommandQueue?
        var ciContext   : CIContext?
    }
}

