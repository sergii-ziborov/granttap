import Foundation

struct AuditEvent: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Double
    let action: String
    let detail: String
    let outcome: String
}

enum CapabilityUsageKind: String, Codable, CaseIterable {
    case mcp
    case skill
    case cli
}

enum CapabilityOutcome: String, Codable, CaseIterable {
    case success
    case error
    case cancelled
    case unknown
}

enum CapabilityResourceAttribution: String, Codable, CaseIterable {
    case measured
    case attributed
    case estimated
    case unknown
}

struct CapabilityResourceUsage: Codable, Equatable {
    let attribution: CapabilityResourceAttribution
    var cpuTimeMs: Int? = nil
    var cpuUserMs: Int? = nil
    var cpuSystemMs: Int? = nil
    var rssStartBytes: Int? = nil
    var rssEndBytes: Int? = nil
    var peakRssBytes: Int? = nil
    var memoryDeltaBytes: Int? = nil
    var childPeakRssBytes: Int? = nil
    var processCount: Int? = nil
    var ioReadBytes: Int? = nil
    var ioWriteBytes: Int? = nil
    var sampleWindowMs: Int? = nil

    var effectiveCpuTimeMs: Int? {
        if let cpuTimeMs { return cpuTimeMs >= 0 ? cpuTimeMs : nil }
        let parts = [cpuUserMs, cpuSystemMs].compactMap { $0 }.filter { $0 >= 0 }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { total, value in
            let result = total.addingReportingOverflow(value)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    var effectivePeakRssBytes: Int? {
        [peakRssBytes, childPeakRssBytes, rssStartBytes, rssEndBytes]
            .compactMap { $0 }.filter { $0 >= 0 }.max()
    }
}

struct CapabilityUsageEvent: Codable, Identifiable, Equatable {
    let id: String
    let sourceId: String
    /// Authenticated relay room that produced this observation. Nil is retained
    /// only for legacy/local global history and must never match a chat detail.
    var sourceRoom: String? = nil
    var agent: String? = nil
    var model: String? = nil
    let kind: CapabilityUsageKind
    let name: String
    var sessionId: String?
    let createdAt: Double
    var toolName: String? = nil
    /// Bounded first line of the invoked CLI command, when this is a CLI event.
    var commandPreview: String? = nil
    /// Exact authenticated chat target used by Usage → Chat navigation.
    var deepLinkTarget: CapabilityChatTarget? = nil
    var estimatedContextTokens: Int? = nil
    var estimatedBaselineTokens: Int? = nil
    var durationMs: Int? = nil
    var outcome: CapabilityOutcome? = nil
    var errorClass: String? = nil
    var resource: CapabilityResourceUsage? = nil

    var effectiveOutcome: CapabilityOutcome { outcome ?? .unknown }

    var estimatedTokensSaved: Int? {
        guard let baseline = estimatedBaselineTokens,
              let used = estimatedContextTokens,
              baseline > used else { return nil }
        return baseline - used
    }
}
