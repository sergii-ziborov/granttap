import Foundation
import StoreKit

@MainActor
final class DesktopLicenseStore: ObservableObject {
    static let shared = DesktopLicenseStore()
    typealias EvidenceLoader = () async throws -> [DesktopPurchaseEvidence]

    @Published private(set) var license: DesktopLicense = .checking
    @Published private(set) var product: Product?
    @Published private(set) var purchasing = false
    @Published private(set) var lastError: String?
    let distribution: DesktopLicenseDistribution
    private let bundleID: String
    private let evaluationAllowed: Bool
    private let evidenceLoader: EvidenceLoader
    private let productLoader: () async throws -> [Product]
    private let storeSync: () async throws -> Void
    private var observer: Task<Void, Never>?

    init(distribution: DesktopLicenseDistribution? = nil,
         bundleID: String = Bundle.main.bundleIdentifier ?? "",
         evaluationAllowed: Bool = DesktopLicenseStore.isEvaluationBuild,
         observe: Bool = !AppRuntime.isRunningUnitTests,
         evidenceLoader: EvidenceLoader? = nil,
         productLoader: @escaping () async throws -> [Product] = {
             try await Product.products(for: [DesktopLicense.productID])
         }, storeSync: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        let selected = distribution ?? DesktopLicenseDistribution(rawValue:
            Bundle.main.object(forInfoDictionaryKey: "GrantTapMacLicenseDistribution") as? String ?? "")
            ?? .inAppUnlock
        self.distribution = selected
        self.bundleID = bundleID
        self.evaluationAllowed = evaluationAllowed
        self.evidenceLoader = evidenceLoader ?? { try await Self.readEvidence(selected) }
        self.productLoader = productLoader
        self.storeSync = storeSync
        if observe {
            observer = Task { [weak self] in
                for await update in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    guard update.unsafePayloadValue.productID == DesktopLicense.productID else { continue }
                    await self?.refresh()
                    if case .verified(let transaction) = update { await transaction.finish() }
                }
            }
        }
    }

    deinit { observer?.cancel() }

    nonisolated static var isEvaluationBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    func start() async {
        await refresh()
        guard distribution == .inAppUnlock else { return }
        do {
            product = try await productLoader().first {
                $0.id == DesktopLicense.productID && $0.type == .nonConsumable
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            license = DesktopLicense.resolve(try await evidenceLoader(), distribution: distribution,
                                             bundleID: bundleID, evaluationAllowed: evaluationAllowed)
            lastError = nil
        } catch {
            license = evaluationAllowed ? .evaluation : .notPurchased
            lastError = error.localizedDescription
        }
    }

    func purchase() async {
        guard distribution == .inAppUnlock, let product else {
            lastError = L("The Mac license is not available in this storefront yet.")
            return
        }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
            case .success(.unverified):
                lastError = L("The App Store could not verify this purchase.")
            case .pending:
                lastError = L("Purchase is pending approval or payment confirmation.")
            case .userCancelled: lastError = nil
            @unknown default:
                lastError = L("The App Store returned an unknown purchase result.")
            }
        } catch { lastError = error.localizedDescription }
    }

    func restore() async {
        purchasing = true
        defer { purchasing = false }
        do {
            try await storeSync()
            await refresh()
        } catch { lastError = error.localizedDescription }
    }

    private static func readEvidence(_ distribution: DesktopLicenseDistribution) async throws
        -> [DesktopPurchaseEvidence] {
        if distribution == .paidDownload {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else {
                throw CocoaError(.featureUnsupported)
            }
            let result = try await AppTransaction.shared
            guard case .verified(let purchase) = result else { return [] }
            return [DesktopPurchaseEvidence(identifier: purchase.bundleID,
                verified: true, revoked: false, nonConsumable: false)]
        }
        var evidence: [DesktopPurchaseEvidence] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            evidence.append(DesktopPurchaseEvidence(identifier: transaction.productID,
                verified: true, revoked: transaction.revocationDate != nil,
                nonConsumable: transaction.productType == .nonConsumable))
        }
        return evidence
    }
}
