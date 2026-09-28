import SwiftUI

struct ProjectComputerUsageRow: View {
    let usage: ProjectComputerUsage
    @ObservedObject var model: AppModel
    var work: [ProjectComputerWork.Item] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(displayName).lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: L("%d×"), usage.calls))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let line = ProjectComputerWork.line(work) {
                Text(line).font(.caption)
                    .foregroundStyle(work.first?.working == true ? Theme.ok : Theme.muted)
                    .lineLimit(2)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            if usage.failures > 0 {
                Text(String(format: L("%d failed"), usage.failures))
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        model.connectionRegistry.connections
            .first { $0.id == usage.endpointId }?.displayName ?? usage.endpointId
    }

    private var detail: String? {
        let parts = [
            usage.cpuTimeMs.map { CapabilityResourceFormat.duration($0) },
            usage.peakMemoryBytes.map { CapabilityResourceFormat.bytes($0) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ProjectBindingRow: View {
    let binding: ProjectBindingSummary
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: binding.available ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .frame(width: 24).foregroundColor(binding.available ? Theme.ok : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(binding.displayName.isEmpty ? binding.repositoryId : binding.displayName)
                Text(detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    var detail: String {
        let computer = model.connectionRegistry.connections
            .first(where: { $0.id == binding.endpointId })?.displayName
            ?? shortEndpoint(binding.endpointId)
        let revision = binding.revision.map { String($0.prefix(12)) }
        return [computer, revision].compactMap { $0 }.joined(separator: " · ")
    }

    func shortEndpoint(_ endpoint: String) -> String {
        endpoint.count <= 24 ? endpoint : "\(L("Computer")) \(endpoint.prefix(8))"
    }
}
