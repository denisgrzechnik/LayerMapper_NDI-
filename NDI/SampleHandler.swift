import ReplayKit
import CoreImage
import ImageIO

class SampleHandler: RPBroadcastSampleHandler {
    
    // Jednorazowa alokacja nazwy źródła NDI (C-string)
    private let ndiNamePtr = strdup("iOS Screen")
    private var pNDI_send: OpaquePointer?
    
    /// docelowa liczba klatek – dropujemy resztę
     private let targetFPS: Double = 30
     /// znacznik czasu ostatnio wysłanej klatki
     private var lastFrameTime: CFTimeInterval = 0
     /// jeden współdzielony kontekst CI – zamiast tworzyć go co klatkę
     private let ciContext = CIContext()
     // --------------------------------------------------------------------
    private var pixelBufferPool: CVPixelBufferPool?
    
    // Bufor dla konwersji obrazu
    private var videoBuffer: UnsafeMutablePointer<UInt8>?
    private var videoBufferSize: Int = 0
    
    // MARK: Start
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        guard NDIlib_initialize() else {
            finishBroadcastWithError(
                NSError(domain: "NDI", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "NDI init error"]))
            return
        }
        
        var createDesc = NDIlib_send_create_t()
        createDesc.p_ndi_name = UnsafePointer(ndiNamePtr)      // nazwa źródła
        pNDI_send = NDIlib_send_create(&createDesc)
        
        if pNDI_send == nil {
            finishBroadcastWithError(
                NSError(domain: "NDI", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "NDI send create error"]))
        }
    }
    
    // MARK: Stop
    override func broadcastFinished() {
        if let s = pNDI_send { NDIlib_send_destroy(s) }
        NDIlib_destroy()
        
        // Zwolnij bufor
        if let buffer = videoBuffer {
            buffer.deallocate()
            videoBuffer = nil
        }
        
        // opcjonalnie: free(ndiNamePtr)
    }
    
    // Funkcja do alokacji lub realokacji bufora jeśli potrzeba
    private func ensureBufferSize(width: Int, height: Int) -> UnsafeMutablePointer<UInt8>? {
        let newSize = width * height * 4 // 4 bajty na piksel (RGBA/BGRA)
        
        if videoBufferSize < newSize || videoBuffer == nil {
            // Zwolnij stary bufor jeśli istnieje
            if let buffer = videoBuffer {
                buffer.deallocate()
            }
            
            // Alokuj nowy bufor
            videoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: newSize)
            videoBufferSize = newSize
        }
        
        return videoBuffer
    }
    
    // MARK: Główna pętla klatek
    override func processSampleBuffer(_ sb: CMSampleBuffer,
                                      with type: RPSampleBufferType) {

        // ——— 1. tylko wideo + limiter 30 fps
        guard type == .video,
              let send = pNDI_send,
              let pb   = CMSampleBufferGetImageBuffer(sb) else { return }

        let now = CACurrentMediaTime()
        if now - lastFrameTime < 1.0 / targetFPS { return }
        lastFrameTime = now

        // ——— 2. CIImage + korekta orientacji
        var image = CIImage(cvPixelBuffer: pb)
        if let n = CMGetAttachment(sb, key: RPVideoSampleOrientationKey as CFString,
                                   attachmentModeOut: nil) as? NSNumber,
           let ori = CGImagePropertyOrientation(rawValue: n.uint32Value) {
            switch ori {                 // cofamy obrót ReplayKit-a
            case .left,  .leftMirrored:  image = image.oriented(.right)
            case .right, .rightMirrored: image = image.oriented(.left)
            case .down,  .downMirrored:  image = image.oriented(.up)
            default: break
            }
        }

        let w = Int(image.extent.width.rounded())
        let h = Int(image.extent.height.rounded())

        // ——— 3. CVPixelBuffer z puli (re-use, zero alokacji w pętli)
        if pixelBufferPool == nil {
            CVPixelBufferPoolCreate(nil, nil,
                [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                 kCVPixelBufferWidthKey: w,
                 kCVPixelBufferHeightKey: h] as CFDictionary,
                &pixelBufferPool)
        }
        var outPB: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool!, &outPB)
        guard let npb = outPB else { return }

        ciContext.render(image, to: npb)

        // ——— 4. ramka NDI z *prawidłowym* FPS i aspektem
        var vf = NDIlib_video_frame_v2_t()
        vf.xres = Int32(w)
        vf.yres = Int32(h)
        vf.FourCC = NDIlib_FourCC_type_BGRA

        vf.frame_rate_N = 30          // <<< klucz: meta 30/1 zamiast 30000/1001
        vf.frame_rate_D = 1
        vf.frame_format_type = NDIlib_frame_format_type_progressive
        vf.picture_aspect_ratio = Float(w) / Float(h)

        CVPixelBufferLockBaseAddress(npb, [])
        vf.p_data = CVPixelBufferGetBaseAddress(npb)!.assumingMemoryBound(to: UInt8.self)
        vf.line_stride_in_bytes = Int32(CVPixelBufferGetBytesPerRow(npb))

        // PTS z ReplayKit (opcjonalnie dokładniejsze od CACurrentMediaTime)
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        vf.timestamp = Int64(Double(pts.value) / Double(pts.timescale) * 1_000_000)

        NDIlib_send_send_video_v2(send, &vf)     // (możesz przełączyć na _async_v2)
        CVPixelBufferUnlockBaseAddress(npb, [])
    }


    }
