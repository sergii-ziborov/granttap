# Desktop licensing

`DesktopLicense.swift` separates the one-time Mac purchase from the optional
Personal service subscription. The shared policy accepts only verified,
unrevoked evidence for the configured distribution. A subscription is not a
Mac license. Development evaluation is explicit and grants no production
self-hosting license.

A verified sandbox `AppTransaction` grants a seven-day TestFlight evaluation
of Mac control and own-relay features. The first launch is recorded for the
Apple app transaction and build number; installing a new TestFlight build
starts a new evaluation. The record is local to the Mac and is never treated
as a purchase. Production App Store transactions cannot enter this path.
An account-linked Mac can use the managed relay as a companion while the same
account has a verified Personal subscription. This route does not unlock local
agent control or self-hosting; those still use the standalone Mac license.
Paired account history remains inspectable when remote authorization expires;
opening that view never renews transport or grants local control.
If StoreKit evidence is unavailable at startup, the license screen offers an
explicit App Store verification retry. A successful verified sandbox result
keeps the evaluation available for that process while StoreKit is intermittent.

`DesktopLicenseStore.swift` reads StoreKit's verified current entitlements for
the non-consumable `com.ziborov.granttap.mac.license`, or a verified
`AppTransaction` for a separately paid-download edition. It never persists a
boolean as proof of purchase. Restore calls Apple's sync; transaction updates
recheck the entitlement. A network failure does not turn an unverified purchase
into a valid license. Apple's signed cached entitlement remains authoritative
for offline use.

`DesktopLicenseView.swift` is the Mac purchase/restore entry point and uses
StoreKit's localized price when no evaluation is active. Distribution configuration and App Store Connect
must describe the same product; source publication is not a paid app receipt.
When it is the root screen for a locked license, Back opens Devices so the
local MCP and account connection remain inspectable.
Tests live in `GrantTapTests/Features/DesktopLicensing`.

The service integration tests compile only in `GrantTapCommerceTests`, selected
by the `GrantTap Commerce` scheme in `apps/ios/commerce-project.yml`. The ordinary
receipt and policy suite uses injected evidence and never purchases a product.
