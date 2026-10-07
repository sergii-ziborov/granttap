# Subscription Entitlements

This feature owns StoreKit product discovery, verified entitlement reduction,
purchase/restore/manage actions, and the subscription screen. It never receives
chat text, agent credentials, pairing keys, or provider tokens.

`SubscriptionProduct.swift` defines stable product identifiers and seat limits.
The displayed ladder covers 2, 5, 10 and 15 computers; no 16+ tier is offered.
`SubscriptionEntitlement.swift` reduces verified StoreKit state into the small
policy state consumed by remote infrastructure. `SubscriptionStore.swift` is
the StoreKit boundary. A verified sandbox app transaction grants temporary
relay access for TestFlight testing without claiming a subscription; production
still requires a verified subscription or a direct/self-hosted route.
Launch resolves sandbox and verified receipt access before opening stored
relay rooms. Product discovery continues afterward, then refreshes access
with authoritative subscription status.
`SubscriptionStoreEvidence.swift` uses verified cached
transactions when product discovery is unavailable; successfully reported
status, including revocation and billing retry, takes precedence over that cache. `SubscriptionView.swift` renders localized StoreKit
prices and links to the public Terms and Privacy pages.
On Mac Catalyst, management opens Apple's subscriptions page; iPhone and iPad
use the StoreKit management sheet.

Tests live in
`GrantTapTests/Features/SubscriptionEntitlements/SubscriptionEntitlementTests.swift`.
The top-level architecture and public billing constraints are documented in
`docs/subscriptions.md`.
