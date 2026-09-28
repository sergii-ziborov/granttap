import SwiftUI

/// Per-call evidence. Context size is not model billing; agent shares are not
/// measurements of the command's isolated process tree.
struct ActivityCommandMetrics {
    let entry: ActivityEntry

    private var singleCapability: ObservedCapability? {
        entry.capabilities?.count == 1 ? entry.capabilities?.first : nil
    }

    var resource: CapabilityResourceUsage? {
        let resources = (entry.capabilities ?? []).compactMap(\.resource)
            .filter { $0.attribution != .unknown }
        guard let first = resources.first, resources.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var durationMs: Int? { valid(entry.durationMs ?? singleCapability?.durationMs) }
    var contextTokens: Int? { valid(entry.estimatedContextTokens ?? singleCapability?.estimatedContextTokens) }
    var cpuTimeMs: Int? { resource?.effectiveCpuTimeMs }
    var peakMemoryBytes: Int? { resource?.effectivePeakRssBytes }

    /// Percent of one CPU core, averaged over the reported measurement window.
    /// Multiple cores may legitimately exceed 100%; no wall-time guess is used.
    var averageCpuPercent: Double? {
        guard let cpu = cpuTimeMs, let window = resource?.sampleWindowMs, window > 0 else { return nil }
        return Double(cpu) / Double(window) * 100
    }

    var approximate: Bool { resource?.attribution == .attributed || resource?.attribution == .estimated }

    private var isMcpServerSample: Bool {
        entry.capabilities?.contains(where: { $0.kind == .mcp && $0.resource == resource }) == true
    }

    var source: String {
        switch resource?.attribution {
        case .measured: return L("Measured for this call")
        case .attributed:
            return isMcpServerSample ? L("Nearby MCP server sample") : L("Approximate share of agent processes")
        case .estimated: return L("Estimated resources")
        case .unknown, nil: return L("Not reported")
        }
    }

    var resourceNote: String {
        switch resource?.attribution {
        case .attributed:
            return isMcpServerSample
                ? L("RAM comes from a nearby sample of the MCP server processes; it is not the isolated memory cost of this call.")
                : L("CPU and RAM are approximate shares of sampled agent processes, including agent overhead. They are not isolated command measurements.")
        case .estimated: return L("The computer reported estimated resources for this call.")
        case .measured: return L("CPU above 100% means more than one core was used.")
        case .unknown, nil: return L("No resource measurement was retained for this call.")
        }
    }

    private func valid(_ value: Int?) -> Int? {
        value.flatMap { $0 >= 0 ? $0 : nil }
    }
}

struct ActivityCommandMetricsSection: View {
    let metrics: ActivityCommandMetrics

    var body: some View {
        Section {
            row("Duration", value: metrics.durationMs.map(duration), id: "duration")
            row("Average CPU (1 core)", value: metrics.averageCpuPercent.map {
                qualified(String(format: "%.1f%%", $0))
            }, id: "cpu")
            row("CPU time", value: metrics.cpuTimeMs.map { qualified(duration($0)) }, id: "cpuTime")
            row("Peak RAM (RSS)", value: metrics.peakMemoryBytes.map {
                qualified(CapabilityResourceFormat.bytes($0))
            }, id: "memory")
            row("Model tokens", value: L("Not reported per command"), id: "modelTokens")
            row("Estimated context tokens", value: metrics.contextTokens.map {
                "~\(Format.tokens($0)) tok"
            }, id: "contextTokens")
            row("Resource source", value: metrics.source, id: "source")
        } header: {
            Text(L("Resources"))
        } footer: {
            Text(L("Context tokens estimate the command arguments and result. Model usage belongs to the reply and cannot be divided reliably between commands.")
                 + "\n" + metrics.resourceNote)
        }
    }

    private func row(_ label: String, value: String?, id: String) -> some View {
        CompatLabeledContent(L(label), value: value ?? L("Not reported"))
            .accessibilityIdentifier("chat.metrics.\(id)")
    }

    private func duration(_ value: Int) -> String {
        value == 0 ? String(format: L("%dms"), 0) : CapabilityResourceFormat.duration(value)
    }

    private func qualified(_ value: String) -> String {
        metrics.approximate ? "~\(value)" : value
    }
}
