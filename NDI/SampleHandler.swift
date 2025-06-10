import ReplayKit
import CoreImage
import ImageIO 

class SampleHandler: RPBroadcastSampleHandler {
    
    // Jednorazowa alokacja nazwy źródła NDI (C-string)
    private let ndiNamePtr = strdup("iOS Screen")
    private var pNDI_send: OpaquePointer?
    
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

        guard type == .video,
              let send = pNDI_send,
              let pb   = CMSampleBufferGetImageBuffer(sb) else { return }

        // ---------- CIImage z bufora ----------
        var image = CIImage(cvPixelBuffer: pb)

        // ---------- orientacja (cofnij obrót) ----------
        if let num = CMGetAttachment(sb,
                                     key: RPVideoSampleOrientationKey as CFString,
                                     attachmentModeOut: nil) as? NSNumber,
           let ori = CGImagePropertyOrientation(rawValue: num.uint32Value) {

            // „Odwracamy” orientację, żeby obraz wrócił do .up
            switch ori {
            case .left,  .leftMirrored:   image = image.oriented(.right)
            case .right, .rightMirrored:  image = image.oriented(.left)
            case .down,  .downMirrored:   image = image.oriented(.up)     // 180°
            default: break                           // .up / .upMirrored – zostawiamy
            }
        }

        // ---------- nowe wymiary ----------
        let w = Int(image.extent.width.rounded())
        let h = Int(image.extent.height.rounded())

        // ---------- bufor BGRA ----------
        var outPB: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_32BGRA,
                            attrs, &outPB)
        guard let npb = outPB else { return }

        // render CIImage → CVPixelBuffer
        CIContext().render(image, to: npb)

        // ---------- wysyłka NDI ----------
        var vf = NDIlib_video_frame_v2_t()
        vf.xres = Int32(w)
        vf.yres = Int32(h)
        vf.FourCC = NDIlib_FourCC_type_BGRA

        CVPixelBufferLockBaseAddress(npb, [])
        vf.p_data = CVPixelBufferGetBaseAddress(npb)!.assumingMemoryBound(to: UInt8.self)
        vf.line_stride_in_bytes = Int32(CVPixelBufferGetBytesPerRow(npb))
        vf.timestamp = Int64(CACurrentMediaTime() * 1_000_000)   // µs
        NDIlib_send_send_video_v2(send, &vf)
        CVPixelBufferUnlockBaseAddress(npb, [])
    }

    }

