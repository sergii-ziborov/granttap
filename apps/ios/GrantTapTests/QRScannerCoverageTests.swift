import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class QRScannerCoverageTests: XCTestCase {
    func testScannerSurfaceRendersDeniedAndUnavailableStates() {
        assertRendered(QRScanView(
            onCode: { _ in }, onCancel: {},
            cameraAuthorization: CameraAuthorizationStub(status: .denied)
        ))
        assertRendered(QRScanView(
            onCode: { _ in }, onCancel: {},
            cameraAuthorization: CameraAuthorizationStub(status: .restricted)
        ))
        _ = SystemQRScannerCameraAuthorization().videoStatus
    }

    func testScannerControllerHandlesEveryAuthorizationBranchWithoutCamera() {
        let cases: [(AVAuthorizationStatus, Bool)] = [
            (.denied, false), (.restricted, false), (.authorized, false),
            (.notDetermined, false), (.notDetermined, true),
        ]
        for (status, grant) in cases {
            let auth = CameraAuthorizationStub(status: status, grantsAccess: grant)
            let controller = ScannerViewController(cameraAuthorization: auth)
            var unavailable = 0
            controller.onCameraUnavailable = { unavailable += 1 }
            controller.loadViewIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            controller.viewDidLayoutSubviews()
            controller.viewDidAppear(false)
            let output = AVCaptureMetadataOutput()
            controller.metadataOutput(
                output, didOutput: [],
                from: AVCaptureConnection(inputPorts: [], output: output)
            )
            controller.viewWillDisappear(false)
            XCTAssertGreaterThanOrEqual(unavailable, 1)
            if status == .notDetermined { XCTAssertEqual(auth.requestCount, 1) }
        }
    }

    func testCoordinatorDeliversOnlyTheFirstDecodedValue() {
        var values: [String] = []
        let coordinator = QRScannerRepresentable.Coordinator { values.append($0) }
        coordinator.deliver("first")
        coordinator.deliver("second")
        XCTAssertEqual(values, ["first"])
    }

    private func assertRendered<V: View>(
        _ view: V, file: StaticString = #filePath, line: UInt = #line
    ) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 4_000, file: file, line: line)
        window.isHidden = true
    }
}

private final class CameraAuthorizationStub: QRScannerCameraAuthorizing {
    let videoStatus: AVAuthorizationStatus
    let grantsAccess: Bool
    var requestCount = 0

    init(status: AVAuthorizationStatus, grantsAccess: Bool = false) {
        videoStatus = status
        self.grantsAccess = grantsAccess
    }

    func requestVideoAccess(_ completion: @escaping (Bool) -> Void) {
        requestCount += 1
        completion(grantsAccess)
    }
}
