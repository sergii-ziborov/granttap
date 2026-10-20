# SubscriptionRetention

Optional cancellation support, a server-authorized Apple promotional offer, and feedback.
The Subscription screen keeps direct Apple management available. Cancellation is always
performed by Apple; feedback and offers never delay or replace it. TestFlight stays free.

The account service verifies production purchase history, signs a one-month offer and
records redemption once per account. The client uses localized StoreKit prices and
requires the exact promotional offer and period. No signing key is stored in the app.
Optional feedback is account-scoped, encrypted at rest on the account server, and is
removed when the account is deleted. Product documentation describes its retention.

## Engineering entry points

- [Engineering contract](../../../../../AGENTS.md).
- [Account API and offer validation](SubscriptionRetentionAPI.swift).
- [StoreKit purchase](SubscriptionRetentionPurchase.swift).
- [Cancellation and feedback UI](SubscriptionCancellationView.swift).
- Feature-owned unit tests are in the separate Xcode test target:
  [SubscriptionRetentionTests](../../../GrantTapTests/Features/SubscriptionRetention/SubscriptionRetentionTests.swift).
  XCTest sources are not compiled into the shipping app.
