import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A code another phone can scan, drawn from text on this one.
struct QRCodeImage: View {
    let text: String
    var size: CGFloat = 220

    static func image(for text: String, scale: CGFloat = 8) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        if let image = Self.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .accessibilityLabel(L("Invite code"))
        } else {
            Text(L("The code could not be drawn; copy the invite instead."))
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}
