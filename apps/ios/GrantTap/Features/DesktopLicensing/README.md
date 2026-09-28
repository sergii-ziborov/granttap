# Desktop licensing

`DesktopLicense.swift` separates the one-time Mac purchase from the optional
Personal service subscription. The shared policy accepts only verified,
unrevoked evidence for the configured distribution. A subscription is not a
Mac license. Development evaluation is explicit and grants no production
self-hosting license.

`DesktopLicenseStore.swift` reads StoreKit's verified current entitlements for
the non-consumable `com.ziborov.granttap.mac.license`, or a verified
`AppTransaction` for a separately paid-download edition. It never persists a
boolean as proof of purchase. Restore calls Apple's sync; transaction updates
recheck the entitlement. A network failure does not turn an unverified purchase
into a valid license. Apple's signed cached entitlement remains authoritative
for offline use.

`DesktopLicenseView.swift` is the Mac purchase/restore entry point and uses
StoreKit's localized price. Distribution configuration and App Store Connect
must describe the same product; source publication is not a paid app receipt.
Tests live in `GrantTapTests/Features/DesktopLicensing`.

The service integration tests compile only in `GrantTapCommerceTests`, selected
by the `GrantTap Commerce` scheme in `apps/ios/commerce-project.yml`. The ordinary
receipt and policy suite uses injected evidence and never purchases a product.
