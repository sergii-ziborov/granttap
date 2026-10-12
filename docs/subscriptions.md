# Mac license and optional Personal subscription

GrantTap Mac uses a one-time **USD 39.99 Mac License** purchase.
The universal App Store configuration is a free download plus the
non-consumable `com.ziborov.granttap.mac.license` unlock. USD 39.99 is the
confirmed US launch price; public purchase availability requires Apple approval. The
native purchase sheet controls localized price, taxes and availability.
A paid Mac purchase is independent of Personal; cancelling Personal does not
remove the Mac license. Restore Purchases rechecks verified StoreKit evidence.
TestFlight Mac builds have a separate seven-day evaluation of local control and
own-relay features. It begins on first launch for each Apple app transaction
and build; a new TestFlight build resets the evaluation. This is not a Mac
purchase or a Personal subscription, and production App Store builds do not
receive it.

## Personal

The Personal monthly tiers are USD 1.99 for up to two computers, 3.99 for up
to five, 5.99 for up to ten, and 9.99 for up to fifteen. Agents are not counted. Eligible new subscribers
may receive a seven-day introductory trial. Auto-renewal, trial eligibility,
price and refunds follow Apple's purchase sheet. Manage or restore in Settings.
The same Apple Account can restore a universal app subscription on Mac and phone.

Product IDs: `com.ziborov.granttap.personal.solo.monthly`,
`com.ziborov.granttap.personal.monthly`,
`com.ziborov.granttap.personal.fleet.monthly`, and
`com.ziborov.granttap.personal.studio.monthly`. Keep them in one subscription group.
Personal pays for managed encrypted relay delivery, bounded queues and supported
APNs wake-up. It does not provide model tokens or an unrestricted web client.
Personal purchases are bound to the GrantTap passkey account through Apple's
appAccountToken. The account service independently verifies production Apple
signatures and atomically admits stable computer identities for the chosen
2/5/10/15-seat plan. QR rooms and agent sessions do not consume extra seats.
The commercial relay verifies short-lived signed admission independently; a
room credential alone does not prove a paid entitlement. Own-relay mode does
not use paid admission. Sandbox testing and operator-issued beta grants remain
separate from production subscriptions. An outage never erases cached history.

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
