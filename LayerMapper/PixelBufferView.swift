import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct PixelBufferView: View {
    let pixelBuffer: CVPixelBuffer
    
    // Zachowujemy proporcje obrazu źródłowego
    private var aspectRatio: CGFloat {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let ratio = CGFloat(width) / CGFloat(height)
      //  print("Original aspect ratio: \(ratio) (width: \(width), height: \(height))")
        return ratio
    }
    
    private var ciImage: CIImage {
        // Tworzymy CIImage z jawnym ustawieniem przestrzeni kolorów
        let tempImage = CIImage(cvPixelBuffer: pixelBuffer)
       // print("Created CIImage from CVPixelBuffer")
        return tempImage
    }
    
    // Tworzymy kontekst z jawnym ustawieniem przestrzeni kolorów
    private static let ciContext: CIContext = {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let options: [CIContextOption: Any] = [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ]
        return CIContext(options: options)
    }()
    
    var body: some View {
        GeometryReader { geo in
            // Próbujemy utworzyć CGImage. Jeśli się uda, pokazujemy obraz i logujemy w onAppear.
            if let cgImage = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Color.black)
                    .onAppear {
                      //  print("Created CGImage from CIImage, size: \(cgImage.width) x \(cgImage.height)")
                      //  print("View size: \(geo.size.width) x \(geo.size.height)")
                    }
            } else {
                Color.black
                    .onAppear {
                      //  print("Failed to create CGImage from CIImage")
                    }
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
    }
}

