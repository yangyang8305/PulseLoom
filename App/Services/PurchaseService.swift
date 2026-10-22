import Combine
import Foundation
import PulseLoomCore
import StoreKit
import UIKit

@MainActor final class PurchaseService: ObservableObject {
    enum Outcome: Equatable {
        case idle, purchasing, success, cancelled, pending, restored, none
        case failed(String)
    }
    /// Called synchronously after the authoritative entitlement value changes on MainActor.
    var entitlementDidChange: (() -> Void)?
    @Published private(set) var pro = false {
        didSet { if pro != oldValue { entitlementDidChange?() } }
    }
    @Published private(set) var product: Product?
    @Published private(set) var outcome: Outcome = .idle
    @Published private(set) var loading = false
    let productID =
        Bundle.main.object(forInfoDictionaryKey: "ProProductID") as? String
        ?? "com.yoyo.PulseLoom.pro.lifetime"
    private var listener: Task<Void, Never>?
    init() {
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = result {
                    await self.refresh()
                    await t.finish()
                }
            }
        }
        Task {
            await refresh()
            await load()
        }
    }
    deinit { listener?.cancel() }
    func load() async {
        loading = true
        defer { loading = false }
        do {
            product = try await Product.products(for: [productID]).first
            if product == nil { outcome = .failed(T("purchase.unavailable")) }
        } catch { outcome = .failed(UserFacingError.message(error, fallback: "purchase.unavailable")) }
    }
    func refresh() async {
        var valid = false
        for await r in Transaction.currentEntitlements {
            if case .verified(let t) = r, t.productID == productID, t.revocationDate == nil { valid = true }
        }
        pro = valid
    }
    var canPurchase: Bool { AppStore.canMakePayments && product != nil && outcome != .purchasing }
    func buy() async {
        guard outcome != .purchasing else { return }
        guard AppStore.canMakePayments, let product else {
            outcome = .failed(T("purchase.unavailable"))
            return
        }
        outcome = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let t) = result, t.productID == productID, t.revocationDate == nil else {
                    throw LoomError.failure(.purchaseUnverified)
                }
                await refresh()
                await t.finish()
                outcome = pro ? .success : .failed(T("error.purchaseNotActive"))
            case .userCancelled: outcome = .cancelled
            case .pending: outcome = .pending
            @unknown default: outcome = .failed(T("purchase.unavailable"))
            }
        } catch { outcome = .failed(UserFacingError.message(error, fallback: "purchase.unavailable")) }
    }
    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
            outcome = pro ? .restored : .none
        } catch { outcome = .failed(UserFacingError.message(error, fallback: "purchase.unavailable")) }
    }
    func refund() async {
        guard
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(
                where: { $0.activationState == .foregroundActive })
        else { return }
        do {
            for await r in Transaction.currentEntitlements {
                if case .verified(let t) = r, t.productID == productID {
                    _ = try await t.beginRefundRequest(in: scene)
                    return
                }
            }
            outcome = .none
        } catch { outcome = .failed(UserFacingError.message(error, fallback: "purchase.unavailable")) }
    }
}
