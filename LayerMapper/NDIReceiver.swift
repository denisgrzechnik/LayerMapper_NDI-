import Foundation
import CoreVideo
import Accelerate

/// Prosty odbiornik NDI → CVPixelBuffer BGRA
final class NDIReceiver {
    let queue = FrameQueue(capacity: 32)
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: – start
    init?(sourceIndex idx: Int) {
        let finder = NDIEnvironment.shared.finder

        var cnt: UInt32 = 0
        guard let ptr = NDIlib_find_get_current_sources(finder, &cnt),
              idx < Int(cnt)
        else { return nil }

        var src = ptr[idx]                       // <- już poza guardem
        // -----------------------------------------------------------

        var desc = NDIlib_recv_create_v3_t()
        desc.color_format = NDIlib_recv_color_format_BGRX_BGRA

        guard let r = NDIlib_recv_create_v3(&desc) else { return nil }
        NDIlib_recv_connect(r, &src)

        _recv = r
        loopQueue.async { [weak self] in self?.captureLoop() }
    }

    // MARK: – stop
    deinit {
        alive = false
        if let r = _recv { NDIlib_recv_destroy(r) }
    }

    // MARK: – capture loop
    private let loopQueue = DispatchQueue(label: "ndiRecv.loop")
    private var _recv: OpaquePointer!
    private var alive = true

    private func captureLoop() {
        var v = NDIlib_video_frame_v2_t()
        while alive {
            let t = NDIlib_recv_capture_v2(_recv, &v, nil, nil, 1000)
            guard t == NDIlib_frame_type_video else { continue }

            if let pb = pixelBuffer(from: &v) {
                queue.push(pb)           // wrzutka do bufora
                // onFrame?(pb)          // ← usuń albo zostaw – jak wolisz
            }
            NDIlib_recv_free_video_v2(_recv, &v)
        }
    }

    /// Tworzy CVPixelBuffer z ramki NDI z odpowiednią konwersją kolorów
    private func pixelBuffer(from f: inout NDIlib_video_frame_v2_t) -> CVPixelBuffer? {
        // Przygotowanie atrybutów dla bufora pikseli
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(f.xres), Int(f.yres),
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pb)
        guard let px = pb else { return nil }

        CVPixelBufferLockBaseAddress(px, [])
        defer { CVPixelBufferUnlockBaseAddress(px, []) }

        let dst = CVPixelBufferGetBaseAddress(px)!
        
        // Obsługa różnych formatów kolorów
        if f.FourCC == NDIlib_FourCC_type_BGRA {
            // Bezpośrednie kopiowanie dla BGRA
            memcpy(dst, f.p_data, Int(f.line_stride_in_bytes) * Int(f.yres))
        
        } else {
            // Fallback dla innych formatów - kopiowanie linia po linii
            for y in 0..<Int(f.yres) {
                let srcLine = f.p_data.advanced(by: y * Int(f.line_stride_in_bytes))
                let dstLine = dst.advanced(by: y * CVPixelBufferGetBytesPerRow(px))
                memcpy(dstLine, srcLine, min(Int(f.line_stride_in_bytes),
                                             CVPixelBufferGetBytesPerRow(px)))
            }
        }
        
        // Ustawienie przestrzeni kolorów dla bufora pikseli
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(px, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
            // Dodajemy metadane kolorów dla YUV (BT.709)
            CVBufferSetAttachment(px, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(px, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(px, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        }
        
        return px
    }
    
    /// Konwersja z UYVY (YUV 4:2:2) do BGRA z użyciem tylko podstawowych operacji na wskaźnikach
    private func convertUYVYtoBGRA(from f: NDIlib_video_frame_v2_t, to pixelBuffer: CVPixelBuffer) {
        let width = Int(f.xres)
        let height = Int(f.yres)
        let srcStride = Int(f.line_stride_in_bytes)
        let dstStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        // Uzyskujemy wskaźniki do danych źródłowych i docelowych
        let srcData = f.p_data
        let dstData = CVPixelBufferGetBaseAddress(pixelBuffer)!
        
        // Tworzymy tablice bajtów do przechowywania danych
        var srcBytes = [UInt8](repeating: 0, count: srcStride * height)
        
        // Kopiujemy dane źródłowe do tablicy bajtów
        memcpy(&srcBytes, srcData, srcStride * height)
        
        // Ręczna konwersja UYVY do BGRA
        // Format UYVY: U0, Y0, V0, Y1, U2, Y2, V2, Y3, ...
        for y in 0..<height {
            for x in 0..<(width/2) {
                // Obliczamy offsety dla źródła i celu
                let srcOffset = y * srcStride + x * 4
                let dstOffset1 = y * dstStride + x * 8
                let dstOffset2 = y * dstStride + x * 8 + 4
                
                // Odczytujemy wartości YUV z tablicy bajtów
                let u = srcBytes[srcOffset]
                let y0 = srcBytes[srcOffset + 1]
                let v = srcBytes[srcOffset + 2]
                let y1 = srcBytes[srcOffset + 3]
                
                // Konwersja YUV do RGB według standardu BT.709
                let y0f = Float(y0) - 16
                let y1f = Float(y1) - 16
                let uf = Float(u) - 128
                let vf = Float(v) - 128
                
                // Pierwszy piksel
                var r0 = Int(1.164 * y0f + 1.793 * vf)
                var g0 = Int(1.164 * y0f - 0.213 * uf - 0.533 * vf)
                var b0 = Int(1.164 * y0f + 2.112 * uf)
                
                // Drugi piksel
                var r1 = Int(1.164 * y1f + 1.793 * vf)
                var g1 = Int(1.164 * y1f - 0.213 * uf - 0.533 * vf)
                var b1 = Int(1.164 * y1f + 2.112 * uf)
                
                // Ograniczamy wartości do zakresu 0-255
                r0 = max(0, min(255, r0))
                g0 = max(0, min(255, g0))
                b0 = max(0, min(255, b0))
                r1 = max(0, min(255, r1))
                g1 = max(0, min(255, g1))
                b1 = max(0, min(255, b1))
                
                // Tworzymy tablice bajtów dla pikseli BGRA
                var bgra0: [UInt8] = [UInt8(b0), UInt8(g0), UInt8(r0), 255]
                var bgra1: [UInt8] = [UInt8(b1), UInt8(g1), UInt8(r1), 255]
                
                // Kopiujemy dane do bufora docelowego
                memcpy(dstData.advanced(by: dstOffset1), &bgra0, 4)
                memcpy(dstData.advanced(by: dstOffset2), &bgra1, 4)
            }
        }
    }
}

