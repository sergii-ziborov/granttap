# Subscription Entitlements

This feature owns StoreKit product discovery, verified entitlement reduction,
purchase/restore/manage actions, and the subscription screen. It never receives
chat text, agent credentials, pairing keys, or provider tokens.

`SubscriptionProduct.swift` defines stable product identifiers and seat limits.
`SubscriptionEntitlement.swift` reduces verified StoreKit state into the small
policy state consumed by remote infrastructure. `SubscriptionStore.swift` is
the StoreKit boundary. `SubscriptionView.swift` renders localized StoreKit
prices and links to the public Terms and Privacy pages.

Tests live in
`GrantTapTests/Features/SubscriptionEntitlements/SubscriptionEntitlementTests.swift`.
The top-level architecture and public billing constraints are documented in
`docs/subscriptions.md`.
