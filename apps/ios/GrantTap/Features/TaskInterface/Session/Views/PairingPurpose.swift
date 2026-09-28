import Foundation

/// Device pairing and Mesh membership have different entry points.
enum PairingPurpose {
    case computer
    case joinProject

    var title: String {
        switch self {
        case .computer: return L("Add a device")
        case .joinProject: return L("Join a Mesh")
        }
    }

    var scanExplanation: String {
        switch self {
        case .computer:
            return L("Scan a one-time QR from a Mac or PC, or a controller QR shown in Settings on a trusted iPhone or iPad. Existing connections stay.")
        case .joinProject:
            return L("Scan a one-time Mesh invite from its owner. This device receives only the permitted scope and role. Computers are paired separately.")
        }
    }

    func accepts(_ pairing: Pairing) -> Bool {
        self == .computer || (pairing.isHub && pairing.inviteKind != "company")
    }

    func rejectionMessage(for pairing: Pairing) -> String {
        if pairing.inviteKind == "company" {
            return L("This code joins a company account. Add it in Settings → Connections; use a Mesh invite here.")
        }
        return L("This code links a computer. Add computers in Settings → Connections; use a Mesh invite here.")
    }
}
