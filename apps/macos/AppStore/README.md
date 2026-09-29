# Mac App Store preparation

This directory contains upload-ready listing text, the commerce specification
and an archive entry point. It does not establish that Apple has accepted a Mac
platform, product, distribution certificate or build. Do not submit for review
until the exact release passes the repository's physical gate and store testing.

Selected architecture: universal free download and a non-consumable $39.99 Mac
License (`com.ziborov.granttap.mac.license`), plus the existing Personal group.
This shares phone subscriptions through the same Apple Account. The Mac platform uses the existing `com.ziborov.granttap` record so Personal
subscriptions share the same Apple Account entitlement. Keep the phone download
free; the Mac purchase is a separate permanent unlock. This platform choice
becomes permanent once Apple approves multiple platforms.

In App Store Connect, configure the launch purchase price in the US storefront,
localized title/description, screenshot for review, purchase availability and
family-sharing choice. Keep the existing 1/5/10-computer Personal subscriptions
in one group with their existing product IDs. Do not create duplicate tiers.
Verify the paid-app agreement, tax and banking details with the account owner.
Configure the Mac developer-tools category, privacy policy, support URL, content
rights and review contact using verified account data. Final export-compliance
answers require the owner's confirmation, not assumptions in a build file.

The uploader filters versions strictly by platform and only edits an existing
editable record. Local validation does not require credentials:

```bash
node scripts/appstore/push-metadata.mjs --platform MAC_OS --dry-run
```

After the Mac platform and API access exist, supply `--key`, `--key-id`,
`--issuer`; do not put private keys in this repository. Screenshots go in
`Screenshots/en-US/Mac` and `Screenshots/ru/Mac`. Capture sanitized real release
UI at Apple's accepted desktop dimensions; never upload live private task data
or represent fixture screenshots as real usage. Draft screenshots are not yet
captured for a signed store build.

Run `bash apps/macos/AppStore/archive.sh` with distribution signing configured.
An unsigned archive can be built with `GRANTTAP_UNSIGNED_ARCHIVE=1` for inspection,
but cannot be uploaded. The sandboxed release talks to the separately installed
MCP over authenticated loopback; the Mac app does not embed or download runtime
code into its sandbox. Test purchase, restore, refund, subscription expiry,
local authorization, files and pairing in Apple's sandbox/TestFlight before
submission. Developer ID downloads additionally need signing and notarization.

The `GrantTap Commerce` scheme activates the local `.storekit` catalog solely
for its separate `GrantTapCommerceTests` integration target. Its launch price is not a live App Store product. The default
GrantTap and GrantTap Local schemes use normal live services. Receipt-policy
tests run in the regular gate; StoreKit service tests require the Commerce
scheme, then Apple's sandbox/TestFlight for the signed Mac release.

If local StoreKit tests return `SKInternalErrorDomain Code=3` or no products,
check the selected simulator runtime before changing receipt policy. Apple tracks
a configuration synchronization issue in [this developer forum thread](https://developer.apple.com/forums/thread/826971).
Use a working runtime for local service tests and still verify the signed Mac
release in Apple's sandbox. Refund tests wait for the asynchronous StoreKit
revocation event and exercise the app's transaction observer.

Built-in native About and Help are connected to the main-window Settings flow.
English/Russian Terms, Privacy, licenses, pricing and device help are bundled
for offline reading. Apple's Standard EULA applies until a custom EULA is
actually configured; the Mac terms additionally grant own-relay use.
