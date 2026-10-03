# GrantTap for Mac

The main Mac app builds the same SwiftUI client as iPhone and iPad with Mac
Catalyst. The visible navigation is Now, Tasks, Mesh, and Usage. A Mesh chat may
link several repositories; GitHub and provider projects keep their own meaning.
The same Task, approval, conversation, Knowledge, Governance, member, and
statistics views are compiled from `apps/ios/GrantTap` for all three devices.

The Mac Graph screen uses a local `WKWebView` with Repo Lens Cyberboard and
Three.js when the Mesh has repository analysis reports. The adapter combines
permitted reports from linked repositories and displays their observed files,
symbols, relations, and external services. Missing reports stay empty; it
does not substitute the Repo Lens demonstration graph. The bundled renderer
was generated from the sibling `repo-lens` revision in
`GraphWeb/REPO_LENS_COMMIT` with `GraphWeb/update-vendor.sh`.

## Build

```bash
cd apps/macos
bash build-app.sh
```

The result is `dist/GrantTap.app`. Xcode and the Apple client's Swift Package
dependencies are required. `build-app.sh` embeds the graph resources and signs
the local development build ad hoc. It does not install or publish the app.
The app detects the GrantTap MCP service on this Mac at launch and reads its
local Mesh and Task data. If the service is unavailable, the app offers the MCP
installation instructions and a retry action. Pairing this computer with other
devices is handled separately in Settings; the Mac does not use the iPad's
scan-a-computer onboarding flow. Settings → Device network can install, start and stop the separate relay through
the MCP. Node 22+ and a reachable TLS proxy or VPN are required. It listens on
loopback and must be started again after a reboot. In a paired room, computers
share one configured relay endpoint.

## Protocol inspector

The earlier standalone read-only desktop viewer remains a development
inspector. `swift test` checks its local Engine protocol and scope handling;
`bash build-inspector-app.sh` builds it separately. Its sidebar and views are
not the main Mac product UI.

## License

The first-party Mac source follows the [GrantTap Commercial Source License](../../LICENSE).
The separate [GrantTap MCP](https://github.com/sergii-ziborov/granttap-mcp)
repository is MIT licensed. See [third-party notices](../ios/THIRD_PARTY_NOTICES.md).

## Purchase and Store preparation

The proposed US one-time Mac License is $39.99, using verified StoreKit 2
non-consumable purchases and Restore Purchases. Personal subscriptions are
optional and use the same product IDs as iPhone. Direct address discovery or
fully self-hosted relay operation needs no Personal subscription. See
[commerce details](../../docs/subscriptions.md) and [Mac EULA](DESKTOP_EULA.md).
The App Store price/product is not live until configured and approved by Apple.

Release builds use App Sandbox, outgoing network and user-selected file access.
The external MCP owns all machine execution. Choose **Authorize local Mac access**
to approve a local, PKCE-protected desktop grant; its token lives in the app's
device-only Keychain. This works without the product website. Debug/LocalTest
builds remain explicit source evaluation builds and use the private same-user
socket. They detect MCP at launch and never automatically enter demo mode.

Store preparation is documented in [App Store](AppStore/README.md). A local
ad-hoc build is neither notarized nor an App Store distribution archive. The
store upload requires the owner's distribution signing and provisioning,
paid-app agreement, editable Mac platform record and final physical checks.

For the native App Sandbox connection, code-tower refresh and live Mesh
statistics, use a runtime built from MCP 0.8.28 source or later.
The source release is available on GitHub; an npm tag is a separate publication.
The `embed-graph-resources.sh` Xcode phase includes graph assets before signing,
so App Store archives contain the same graph as local Mac builds.

## Chat history and storage

The chat status strip shows its Project/Mesh. Messages display dates and local
times. The fixed user-message strip jumps to the latest request, then prepares
older requests as you navigate. Native Codex and Claude history loads
backward automatically, including across long runs of commands. A failed load
shows a retry; normal browsing does not require a “Show earlier” button.

Every fetched Mac page is kept in a protected per-chat archive. Settings →
This Mac → Chat history & cache shows its size and can clear this local copy
without changing device connections or provider-owned conversation files.
The nested Provider storage page can inspect Codex, Claude and Cursor storage
using the optional separately installed SweepLoom CLI. Only selected temporary
caches or logs are eligible for confirmed moves to Trash; provider history,
credentials, configuration and databases are inspect-only. Running providers
and changed caches require a fresh review.

## Browse Mesh and repositories

The Mesh screen has a pinned **Mesh / Repositories** switch on Mac, iPad and
iPhone. Mesh preserves coordination and access scopes. Repositories lists reported
repository identities and opens their Mesh scopes and chat executions. Each chat
keeps its original Task and Mesh route. In a Mesh, chats are grouped by their
reported execution repository and show the repository identity and branch.
Previous executions and missing or conflicting repository evidence are labeled
explicitly. Workspace folders without confirmed Git are listed separately.

Working repositories appear first with their observed branches and tasks.
Repository details also show Git state, recent commits and contributors from
the local computer. This requires MCP 0.8.29 source or later. Verified Git reports
combine stale local and remote identities; conflicting checkouts remain separate.
Tasks started in another Mesh are automatically presented under the unique
visible repository Mesh. Original Task IDs, history, routes and permissions are
preserved, and both locations explain the relationship.

## About, Help and legal information

The native **GrantTap → About GrantTap** and **Help → GrantTap Help** menus
open the same pages as Settings in the main window. Terms, Privacy, licenses
and pricing are bundled in English and Russian and readable without internet.
Help covers device QR pairing, computer links, local MCP authorization, hooks,
purchase restoration, Personal and direct/self-hosted delivery.

Optional GrantTap account sign-in uses a passkey shared through the user's
credential provider. The Mac still authorizes its local MCP bridge and links
each phone separately; account sign-in by itself neither imports a pairing key
nor grants a coding app access. A fresh passkey assertion can authorize a
coding app through `granttap.com/connect` when the local bridge is available.
