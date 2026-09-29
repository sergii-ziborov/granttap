# Mac launch commerce

Selected configuration for the existing `com.ziborov.granttap` app record:
add macOS, keep the universal download free, and sell the permanent Mac unlock.
These are the requested launch values; this document does not mean App Store
Connect has accepted or enabled them. Localized amounts come from StoreKit.

| Product | Type | US price | Limit | Group level |
| --- | --- | --- | --- | --- |
| `com.ziborov.granttap.mac.license` | Non-consumable | $39.99 once | Licensed Mac; local control and own relay | — |
| `com.ziborov.granttap.personal.solo.monthly` | Auto-renewable, 1 month | $1.99 | 1 computer | 3 |
| `com.ziborov.granttap.personal.monthly` | Auto-renewable, 1 month | $3.99 | Up to 5 computers | 2 |
| `com.ziborov.granttap.personal.fleet.monthly` | Auto-renewable, 1 month | $5.99 | Up to 10 computers | 1 |

Use the existing Personal subscription group. Level 1 is the largest tier.
Request a seven-day free trial for eligible new subscribers; Apple determines
eligibility within the group. Do not duplicate existing products or reset their
pricing, availability or offers before inspecting their current state.
Family Sharing is not enabled in the prepared catalog. A Mac license does not
include AI-provider charges or the recurring cost of the managed service.
The one-time price pays for Mac control and self-hosting; managed infrastructure
has a separate recurring price, so cancellation preserves the purchased license.

## Product localization

| Product | English title and description | Russian title and description |
| --- | --- | --- |
| Mac | GrantTap Mac License — Permanent Mac license, including personal self-hosting. | Лицензия GrantTap Mac — Постоянная лицензия Mac, включая собственный relay. |
| Solo | Personal 1 — Managed relay for one computer. | Personal 1 — Управляемый relay для одного компьютера. |
| Personal | Personal 5 — Managed relay for up to five computers. | Personal 5 — Управляемый relay для пяти компьютеров. |
| Fleet | Personal 10 — Managed relay for up to ten computers. | Personal 10 — Управляемый relay для десяти компьютеров. |

## App record

- Platform: macOS; version 1.0; primary category Developer Tools.
- Name: GrantTap; copyright: 2026 Serhii Ziborov.
- Listing: [English and Russian metadata](APP_STORE_METADATA.md).
- Website: https://granttap.com; support: https://granttap.com/support.
- Privacy: https://granttap.com/privacy; terms: https://granttap.com/terms.
- Source license: [GrantTap Commercial Source License](../../../LICENSE).
- App Store EULA: Apple Standard EULA unless a custom EULA is actually configured.
- Review contact: use the verified account contact, not a guessed phone/address.
- Supply Mac screenshots and each purchase's review screenshot from the signed
  release. Attach the first Mac in-app purchase to the version submitted for review.

The account owner must handle any outstanding paid-app agreement, tax/banking
requirements, and confirm export-compliance and content-rights answers.
Adding a second approved platform makes the app a universal purchase permanently.

Apple references: [platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms),
[in-app purchase setup](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/),
[Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).
