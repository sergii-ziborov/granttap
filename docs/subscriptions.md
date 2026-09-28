# Mac license and optional Personal subscription

GrantTap Mac is prepared for a one-time **USD 39.99 Mac License** purchase.
The proposed universal App Store configuration is a free download plus the
non-consumable `com.ziborov.granttap.mac.license` unlock. This price is a launch
proposal until the App Store Connect product is configured and approved. The
native purchase sheet controls localized price, taxes and availability.
A paid Mac purchase is independent of Personal; cancelling Personal does not
remove the Mac license. Restore Purchases rechecks verified StoreKit evidence.

## Personal

The existing Personal monthly tiers are USD 1.99 for one computer, 3.99 for up
to five, and 5.99 for up to ten. Agents are not counted. Eligible new subscribers
may receive a seven-day introductory trial. Auto-renewal, trial eligibility,
price and refunds follow Apple's purchase sheet. Manage or restore in Settings.
The same Apple Account can restore a universal app subscription on Mac and phone.

Product IDs: `com.ziborov.granttap.personal.solo.monthly`,
`com.ziborov.granttap.personal.monthly`, and
`com.ziborov.granttap.personal.fleet.monthly`. Keep them in one subscription group.
Personal pays for managed encrypted relay delivery, bounded queues and supported
APNs wake-up. It does not provide model tokens or an unrestricted web client.
Verified StoreKit status determines client access; the relay's room credential
is a transport credential, not a server-side Apple subscription receipt.

## Without a subscription

A licensed Mac can control its local MCP and configure its own relay. Direct
mode publishes a short-lived sealed endpoint address to the managed directory;
the iPhone checks it on connection and periodically while active, then sends
chat traffic to that endpoint. Fully self-hosted mode uses your endpoint for
pairing and delivery; no managed directory is contacted. The iPhone does not
need a separate subscription for that route. Apple Watch uses its paired iPhone.

Use Settings → Device network on Mac. Install/start/stop the local relay there,
and connect iPhone/iPad with the existing one-time QR. Supply a reachable TLS
endpoint or VPN; a computer behind NAT does not become reachable by announcing
an IP address. All computers in a room use the same relay endpoint. Restart the
local relay after a reboot; the app does not install a system-wide relay daemon.
Own-relay APNs is unavailable unless you independently supply the required Apple
server credentials. Foreground connection and history remain available; iOS
background timing is controlled by the system.

[Mac license](../apps/macos/DESKTOP_EULA.md),
[Terms](https://granttap.com/terms), [Privacy](https://granttap.com/privacy).
