# GrantTap subscriptions

GrantTap is planned as a free App Store download with a seven-day introductory
trial for eligible new subscribers. Personal is priced by how many computers a
person links — USD 1.99 for one, 3.99 for up to five, 5.99 for up to ten per
month. Agents are never counted: each linked computer runs as many coding agents
as it can. The App Store purchase sheet is authoritative for the localized
price, taxes, trial eligibility, and renewal terms shown to each customer.

The subscription pays for remote infrastructure: the encrypted relay, APNs
wake-up, bounded server queue, and web remote access. It never buys model tokens
and GrantTap never receives AI-provider credentials or model traffic. Local
agent history and encrypted on-device data remain available when an entitlement
expires. Restore Purchases and Manage Subscription are available in Settings.

The StoreKit product identifiers are
`com.ziborov.granttap.personal.solo.monthly` (1 computer),
`com.ziborov.granttap.personal.monthly` (5), and
`com.ziborov.granttap.personal.fleet.monthly` (10). All three must exist as
auto-renewable monthly subscriptions in one GrantTap subscription group, so a
person moves between tiers as an upgrade or downgrade that Apple prorates, each
with a seven-day free introductory offer. The app reads its price from StoreKit
and never hard-codes one. App Store metadata must link to
[Terms of Use](https://granttap.com/terms) and the
[Privacy Policy](https://granttap.com/privacy).

A direct transport among the phone, watch, and computer on the same Wi-Fi is a
future feature. It is not implemented yet. The first local version is intended
for direct delivery only, without server synchronization or remote history sync.
