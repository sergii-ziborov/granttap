import XCTest
import SwiftUI
import UIKit
@testable import GrantTap

@MainActor
final class FailedDeliveryContrastTests: XCTestCase {
    func testRetryLabelHasReadableContrastInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let image = renderPendingDelivery(style)
            let attachment = XCTAttachment(image: image)
            attachment.name = style == .dark ? "Retry dark" : "Retry light"
            attachment.lifetime = .keepAlways
            add(attachment)
            let pixels = try imagePixels(image)
            let values = (105..<125).flatMap { y in
                (150..<280).map { luminance(pixels, x: $0, y: y) }
            }
            let contrast = (try XCTUnwrap(values.max()) + 0.05)
                / (try XCTUnwrap(values.min()) + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.5,
                "The actual Now Retry label must contrast with its fill in \(style).")
        }
    }

    private func renderPendingDelivery(_ style: UIUserInterfaceStyle) -> UIImage {
        let model = AppModel()
        model.pending = []
        model.questions = []
        model.meshSnapshots = [:]
        model.deliveries = [OutgoingDelivery(id: "retry-contrast", text: "Fixture",
            agent: "codex", cwd: nil, sessionId: nil, requestId: nil, roomId: nil, attachments: [],
            preferredMcp: nil, skill: nil, createdAt: 1, updatedAt: 1,
            attempts: 5, state: .failed, error: "Delivery failed.", nextRetryAt: nil)]
        let frame = CGRect(x: 0, y: 0, width: 430, height: 200)
        let content = ContentView(modelOverride: model).pendingSection
            .frame(width: frame.width, height: frame.height, alignment: .top)
            .background(Theme.bg).ignoresSafeArea()
            .preferredColorScheme(style == .dark ? .dark : .light)
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: frame)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    private func imagePixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 430 * 200 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 430, height: 200,
            bitsPerComponent: 8, bytesPerRow: 430 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 430, height: 200))
        return pixels
    }

    private func luminance(_ pixels: [UInt8], x: Int, y: Int) -> Double {
        let rgb = (0..<3).map { channel -> Double in
            let value = Double(pixels[(y * 430 + x) * 4 + channel]) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
    }
}
