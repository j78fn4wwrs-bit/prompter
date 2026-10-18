import Foundation
import StoreKit
import Combine

/// StoreKit 2 one-time "Pro" unlock. No accounts, no server.
@MainActor
final class ProStore: ObservableObject {
    static let proID = "com.mikejohnson.prompter.pro"

    @Published private(set) var isPro: Bool = false
    @Published private(set) var product: Product?
    @Published var isBusy: Bool = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    await self?.refreshEntitlements()
                }
            }
        }
        await loadProduct()
        await refreshEntitlements()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [ProStore.proID])
            product = products.first
        } catch {
            errorMessage = "Couldn't reach the App Store. Try again later."
        }
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == ProStore.proID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
        await refreshEntitlements()
        if !isPro && errorMessage == nil {
            errorMessage = "No previous Pro purchase found for this Apple Account."
        }
    }
}
