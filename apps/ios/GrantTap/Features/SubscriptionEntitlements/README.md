# Subscription Entitlements

This feature owns StoreKit product discovery, verified entitlement reduction,
purchase/restore/manage actions, and the subscription screen. It never receives
chat text, agent credentials, pairing keys, or provider tokens.

`SubscriptionProduct.swift` defines stable product identifiers and seat limits.
`SubscriptionStorefront.swift` uses Apple's introductory offer and eligibility
to show seven days free; it does not reset trial eligibility on a new build.
`AccountSubscriptionGrant.swift` reads independently verified account access.
The grant is bound to the signed-in session, lasts at most five minutes and
cannot be extended by a network failure. A purchase on iPhone can authorize a
linked Mac's managed relay connection without another trial or purchase.
The displayed ladder covers 2, 5, 10 and 15 computers; no 16+ tier is offered.
`SubscriptionEntitlement.swift` reduces verified StoreKit state into the small
policy state consumed by remote infrastructure. `SubscriptionStore.swift` is
the StoreKit boundary. A verified sandbox app transaction grants temporary
relay access for TestFlight testing without claiming a subscription. A signed-in
tester can also receive a time-limited account grant from the Hetzner account
service when StoreKit cannot return an app transaction. The grant is bound to
that account, expires, and is rechecked for revocation. Production without a
grant still requires a verified subscription or a direct/self-hosted route.
Devices retries account evidence before requesting an App Store refresh, then
reconnects the affected account machine.
Launch resolves verified account access first, then sandbox or receipt evidence
when needed, before opening stored relay rooms. A valid account grant does not
wait for a StoreKit app transaction; verified tester access does not wait for
receipt discovery. Product and subscription status refresh continues after
connection starts. Account grants are still checked for revocation and expiry.
`SubscriptionStoreEvidence.swift` uses verified cached
transactions when product discovery is unavailable; successfully reported
status, including revocation and billing retry, takes precedence over that cache. `SubscriptionView.swift` renders localized StoreKit
prices and links to the public Terms and Privacy pages.
On Mac Catalyst, management opens Apple's subscriptions page; iPhone and iPad
use the StoreKit management sheet.

Personal purchases include the signed-in GrantTap account UUID as Apple's
`appAccountToken`. A production receipt is sent to the account service for an
independent Apple-signature check and stable computer admission. Sandbox
purchases are not production subscriptions. Server outages never erase the
locally verified StoreKit evidence or cached history. Existing purchases without
an account binding require a verified ownership migration before hosted seats
can be issued; the client does not silently attach someone else's receipt.

Tests live in
`GrantTapTests/Features/SubscriptionEntitlements/SubscriptionEntitlementTests.swift`.
The top-level architecture and public billing constraints are documented in
`docs/subscriptions.md`.

Transport change notifications carry effective permission changes only.
Renewing the same grant, changing receipt metadata, or observing initial state
does not tear down existing sockets. Revocation still revalidates every route.
This behavior is shared by development and release builds.
