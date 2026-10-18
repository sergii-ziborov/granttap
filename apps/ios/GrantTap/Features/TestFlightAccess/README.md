# TestFlight access

`TestFlightAccessStore` reads Apple's verified sandbox app transaction for this
bundle. Both Apple clients unlock their commercial features in TestFlight
without a purchase, subscription, or app-managed seven-day countdown. Apple
continues to control when a TestFlight build expires. Production StoreKit
transactions do not qualify. No receipt filename or persisted boolean is proof.

`DesktopLicenseStore` applies that evidence to local Mac and own-relay rights;
`SubscriptionStore` applies it to managed transport. Account and computer
permissions remain independent and the relay still validates its own admission.
A seven-day introductory offer belongs to an auto-renewing subscription and
starts only when an eligible user confirms that subscription with Apple.

Policy and store integration tests live beside DesktopLicensing and in
GrantTapTests/Features/SubscriptionEntitlements.
