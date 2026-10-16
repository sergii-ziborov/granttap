# Mac license and optional Personal subscription

GrantTap Mac uses a one-time **USD 39.99 Mac Local** purchase.
The universal App Store configuration is a free download plus the
non-consumable `com.ziborov.granttap.mac.license` unlock. USD 39.99 is the
confirmed US launch price; public purchase availability requires Apple approval. The
native purchase sheet controls localized price, taxes and availability.
A paid Mac purchase is independent of Personal; cancelling Personal does not
remove the Mac license. Restore Purchases rechecks verified StoreKit evidence.
TestFlight evaluation is separate from paid Mac Local and Apple subscription
trials. A beta evaluation is not a verified production purchase. Its current
status is shown by the app; it is not a promised renewal of a commercial trial.

## Personal

| First-launch plan | US monthly price | Managed publishing computers | Technical product ID |
| --- | --- | --- | --- |
| Personal | $3.99 | 2 | `com.ziborov.granttap.personal.solo.monthly` |
| Personal Plus | $6.99 | 5 | `com.ziborov.granttap.personal.monthly` |
| Fleet | $11.99 | 15 | `com.ziborov.granttap.personal.studio.monthly` |

Only these three monthly subscriptions are in the first commercial catalog.
`com.ziborov.granttap.personal.fleet.monthly` is unused preparation for the old
10-computer offer and is not a launch product. Keep the three active products in
one group, ordered Fleet → Personal Plus → Personal from highest to lowest.
No annual plans or public Legacy tier are offered.

All core features are shared. Stable computers enabled to publish agent work
consume seats; additional agents, sessions, Tasks and projects on the same
computer do not. iPhone, iPad, Watch and controller-only Macs do not consume
publishing-computer seats. Fleet is a personal allowance, not a fifteen-person
enterprise license or SLA. Provider, adapter and runtime limitations still apply.
Repository analysis additionally requires the installed GrantTap Engine.

Active Personal includes managed access on linked Macs without an additional
Mac Local purchase. Mac Local is the separate one-time local/own-relay right.
Personal pays for managed encrypted delivery, bounded queues and supported
background wake. It does not provide AI models, tokens or unlimited compute,
traffic or storage. Eligible new subscribers may receive Apple's configured
seven-day introductory offer; StoreKit determines eligibility, local price,
availability and billing dates. Apple shows the effective date and conditions
of upgrades and downgrades. Manage or restore in Settings.

Purchases are bound to the GrantTap passkey account through Apple's
appAccountToken. The account service independently verifies production Apple
signatures and atomically admits stable computer identities for the 2/5/15-seat
plan. QR rooms and agent sessions do not consume extra seats. The relay verifies
short-lived signed admission independently; room credentials alone are not paid
rights. Own-relay mode does not use paid admission. Sandbox testing and explicit
beta grants remain separate from production purchases. Failed synchronization
must not require another purchase. An outage or cancellation does not delete
local history, images or pairings, or revoke a purchased Mac Local license.

## Without a subscription

A licensed Mac can control its local MCP and configure its own relay. Direct
mode publishes a short-lived sealed endpoint address to the managed directory;
the iPhone checks it on connection and periodically while active, then sends
chat traffic to that endpoint. Fully self-hosted mode uses your endpoint for
pairing and delivery; no managed directory is contacted. The iPhone does not
need a separate subscription for that route. Apple Watch uses its paired iPhone.

Use Devices → Device network on Mac. Install/start/stop the local relay there,
and connect iPhone/iPad with the existing one-time QR. Supply a reachable TLS
endpoint or VPN; a computer behind NAT does not become reachable by announcing
an IP address. All computers in a room use the same relay endpoint. Restart the
local relay after a reboot; the app does not install a system-wide relay daemon.
Own-relay APNs is unavailable unless you independently supply the required Apple
server credentials. Foreground connection and history remain available; iOS
background timing is controlled by the system.

[Mac license](../apps/macos/DESKTOP_EULA.md),
[Terms](https://granttap.com/terms), [Privacy](https://granttap.com/privacy).
