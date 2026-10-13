import SwiftUI
import SceneKit

/// Interactive code city. Camera state survives view settings and colour changes.
struct ProjectTowerScene: UIViewRepresentable {
    let snapshot: ProjectTowerSnapshot
    @Binding var selectedPath: String?
    @Binding var selectedSymbol: String?
    var command: ProjectTowerCameraRequest?
    var settings: ProjectTowerViewSettings

    init(snapshot: ProjectTowerSnapshot, selectedPath: Binding<String?>,
         selectedSymbol: Binding<String?> = .constant(nil), command: ProjectTowerCameraRequest? = nil,
         settings: ProjectTowerViewSettings = .init()) {
        self.snapshot = snapshot
        _selectedPath = selectedPath
        _selectedSymbol = selectedSymbol
        self.command = command
        self.settings = settings
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = ProjectTowerGeometry.void
        view.allowsCameraControl = true
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.automaticTarget = false
        view.defaultCameraController.delegate = context.coordinator
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        view.isAccessibilityElement = true
        view.accessibilityLabel = L("Code towers scene")
        context.coordinator.view = view
        context.coordinator.replaceScene()
        for gesture in view.gestureRecognizers ?? [] {
            gesture.addTarget(context.coordinator, action: #selector(Coordinator.cameraGesture(_:)))
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        context.coordinator.keepRendering()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.defaultCameraController.delegate = nil
        view.scene = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
}
