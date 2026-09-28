# Mac App Store preparation

This directory contains upload-ready listing text, the commerce specification
and an archive entry point. It does not establish that Apple has accepted a Mac
platform, product, distribution certificate or build. Do not submit for review
until the exact release passes the repository's physical gate and store testing.

Proposed architecture: universal free download and a non-consumable $39.99 Mac
License (`com.ziborov.granttap.mac.license`), plus the existing Personal group.
This shares phone subscriptions through the same Apple Account. The alternative
is a separate paid Mac record (`com.ziborov.granttap.mac`); a verified receipt
under the existing free phone bundle ID must never unlock a paid-download Mac.
Adding the Mac platform to a universal record is irreversible; resolve the
owner's requested distribution choice before that App Store Connect action.

In App Store Connect, configure the launch purchase price in the US storefront,
localized title/description, screenshot for review, purchase availability and
family-sharing choice. Keep the existing 1/5/10-computer Personal subscriptions
in one group with their existing product IDs. Do not create duplicate tiers.
Verify the paid-app agreement, tax and banking details with the account owner.
Configure the Mac developer-tools category, privacy policy, support URL, content
rights and review contact using verified account data. Final export-compliance
answers require the owner's confirmation, not assumptions in a build file.

The listing text in `APP_STORE_METADATA.md` is a draft for the account owner.
Configure the corresponding Mac platform and products through App Store Connect.
Screenshots belong in `Screenshots/en-US/Mac` and `Screenshots/ru/Mac`. Capture
sanitized release UI at Apple's accepted desktop dimensions. Draft screenshots
for a signed store build have not been captured yet.

Run `bash apps/macos/AppStore/archive.sh` with distribution signing configured.
An unsigned archive can be built with `GRANTTAP_UNSIGNED_ARCHIVE=1` for inspection,
but cannot be uploaded. The sandboxed release talks to the separately installed
MCP over authenticated loopback; the Mac app does not embed or download runtime
code into its sandbox. Test purchase, restore, refund, subscription expiry,
local authorization, files and pairing in Apple's sandbox/TestFlight before
submission. Developer ID downloads additionally need signing and notarization.

The `GrantTap Commerce` scheme activates the local `.storekit` catalog solely
for the separate `GrantTapCommerceTests` integration target. Its launch price is not a live App Store product. The default
GrantTap and GrantTap Local schemes use normal live services. Receipt-policy
tests run in the regular gate; StoreKit service tests require the Commerce
scheme, then Apple's sandbox/TestFlight for the signed Mac release.
