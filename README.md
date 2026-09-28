# GrantTap for Mac, iPhone, iPad and Apple Watch

GrantTap is a personal control center for local coding agents. See running
Tasks, answer approvals and questions, continue a chat, inspect tool activity,
and organize related repositories in Project Mesh.

A Task keeps its identity and history across provider sessions and computers.
Claude Code and Codex are primary integrations; Cursor is Beta. Other providers
are shown only at the control depth their implementation supports. Provider
accounts and model tokens are separate from GrantTap purchases.

## Mac

The Mac app uses the shared Apple client and the separately installed
[GrantTap MCP](https://github.com/sergii-ziborov/granttap-mcp). It detects the local
runtime, or offers installation when missing. Network connections are managed
in Settings. The release app requests explicit access to the local MCP through
an authenticated loopback connection compatible with the App Sandbox.

The Mac App Store release is being prepared; it is not available for purchase
yet. The proposed price is **USD 39.99 once** for the Mac License. The draft
universal configuration is a free download with a non-consumable Mac unlock.
Final storefront prices and availability are determined by Apple's purchase
sheet. A paid-download alternative requires a separate Mac app record.

A purchased Mac license includes local control and running your own relay for
personal or internal use. It remains valid when a Personal subscription ends,
subject to refunds or revocation. Development builds are evaluation builds and
do not represent a verified production purchase.

## Optional Personal subscription

Personal pays for managed encrypted relay delivery, bounded server queues and
supported background notifications. Proposed/current configured tiers are
USD 1.99/month for one computer, 3.99 for up to five, and 5.99 for up to ten;
Apple's purchase sheet controls the actual offer and any eligible seven-day
trial. Agents are not counted. Restore and manage purchases in Settings.

Without Personal, a licensed Mac can use encrypted endpoint discovery with
direct traffic, or an entirely self-hosted relay. The phone periodically resolves
the announced address while active. Supply a reachable TLS endpoint or VPN;
announcing an address does not configure NAT, router ports or APNs. Own-relay
installation and controls live in Mac Settings. Apple Watch uses its iPhone.

See [purchase and connection modes](docs/subscriptions.md),
[Mac EULA](apps/macos/DESKTOP_EULA.md), [Terms](https://granttap.com/terms),
[Privacy](https://granttap.com/privacy) and [Support](https://granttap.com/support).

## Build and inspect

- [Shared Apple client and Xcode project](apps/ios/README.md)
- [Mac build instructions](apps/macos/README.md)
- [Mac App Store configuration and listing](apps/macos/AppStore/README.md)
- [Third-party notices](apps/ios/THIRD_PARTY_NOTICES.md)

Xcode 26 and XcodeGen generate/build the shared app. The checked-in project
supports iPhone/iPad, Watch and Mac Catalyst. `bash apps/macos/build-app.sh`
creates the local Mac evaluation build. That ad hoc build is neither an App
Store upload nor a notarized distribution. The separate read-only desktop
inspector remains available through `build-inspector-app.sh`.

## Source and license

The publicly readable Apple/Mac source uses the
[GrantTap Commercial Source License](LICENSE), with the Mac end-user terms
above. It is not an MIT grant to redistribute or resell the application.
Earlier copies validly released under MIT retain their original rights.
Third-party components keep their own licenses. The MCP/CLI is MIT licensed;
[relay](https://github.com/sergii-ziborov/granttap-relay) and
[website](https://github.com/sergii-ziborov/granttap-site) have their own licenses.

`PUBLIC_SOURCE.json` records the source revision and SHA-256 of each exported
file. This snapshot contains app/runtime-facing source, tests, public help and
build resources. Internal plans, account credentials and local build state are
excluded. Report vulnerabilities using [Security](SECURITY.md).
