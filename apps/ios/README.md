# GrantTap for iPhone, iPad, and Apple Watch

Subscription purchase, restore, management, verified entitlement reduction,
and the future local-network boundary are documented in
[`../../docs/subscriptions.md`](../../docs/subscriptions.md). Storefront prices
come from StoreKit; the app does not hardcode a purchase price.

The publicly readable SwiftUI source for reviewing coding-agent actions, browsing
active and recently active tasks, reading their latest visible activity, and
replying or starting a new task by voice from iPhone, iPad, or Apple Watch.

The iOS app is a universal iPhone/iPad binary with a minimum deployment target
of iOS/iPadOS 15.0. Apple Watch remains an iPhone companion: iPad supports the
main app workflow, but it cannot pair with or relay state to Apple Watch through
WatchConnectivity.

Apple Watch shows one unified task list: **Needs You** first, then **Active**
and **Recent**, across every connected agent. Task rows show only a large title
and status; opening one starts its compact encrypted activity subscription with
the latest two events, then appends and scrolls new events. With no synchronized
state the watch reports the link status instead of substituting demo tasks.

Codex uses a strict monochrome surface system on iPhone, iPad, and Watch; Claude Code
uses warm ember surfaces and its native capability limits. Watch About contains
product/privacy facts only and deliberately exposes no external links.

English is the default language. Switch between English and Russian in
Settings on iPhone/iPad or from the main task list on Apple Watch.

On iPhone and iPad, dictation evaluates Russian and English recognition candidates from
the same audio and preserves time-aligned English technology names in Russian
speech. Apple Watch uses the system dictation UI, whose locale the app cannot
change programmatically, then locally normalizes common English technology names.

The source is public under the separate GrantTap commercial source license. The
App Store distribution remains a separate, subscription-backed product.

## Project Mesh and Agents & Mesh

**Project Mesh** keeps one Task identity while execution moves between agents or
computers. The Task screen shows the project, its stable Task, current execution
owners, expiring resource claims, and a curated event timeline. A handoff sends a
bounded encrypted Task Capsule—goal, git state, changed files, tests,
dependencies, claims, remaining work, explicit decisions—and never transcripts or
hidden reasoning. The destination works in its own branch or worktree, and the
accepted handoff is verified against a SHA-256 receipt over the exact capsule.

The Task's Runtime section asks each linked Project computer for a bounded page
of Engine-owned Invocation evidence. It shows tool requests, reported results,
denials, and source gaps separately; it never calls a requested edit a verified
file change. Pages are encrypted with the Project key and kept only in memory on
the phone. The section says when a computer's Engine is unavailable.

Technical agent-to-agent questions and advisory conflicts stay inside the mesh.
Product, business, security, destructive, unresolved-conflict, and failed-handoff
decisions reuse the existing Needs You inbox, so nothing appears twice. Opening
one goes to the Task, not to a native session: a Grok Bot actor, an offline
computer, or a handoff still in flight all open, and an answer typed there is
published back to the agent that asked.

Before the handoff button, GrantTap shows a readiness pre-flight — destination,
working tree, claims, target agent, commit. A checkout with uncommitted changes
blocks the handoff on both the phone and the source computer, because a capsule
carries committed facts and that work would otherwise stay behind while the Task
appeared to continue elsewhere.

**Settings → Agents & Mesh** owns the per-agent runtime gates for Claude Code,
Codex, Cursor, and Grok Build plus the Project Mesh switch. Disabling an agent
stops new GrantTap monitoring without uninstalling it or deleting local task,
history, and usage records; pending decisions stay pending.

**Grok Bot** is a scoped persistent-agent endpoint, not a coding-agent
integration. The phone issues a one-time encrypted invite limited to the Projects
you select, the invite is redeemed only by the trusted `granttap mesh connect`
CLI, and the resulting MCP server exposes only task-scoped Mesh operations.
Invite creation, actor enablement, Project scope, and revocation stay in the app
and the CLI, never in a model-callable tool.

## What happens when you reply from the phone

Answering an approval or an agent's `ask` goes back into the session that is
already running and waiting for it. Writing a new message into a chat is a
different path: the computer resumes that chat by running the provider's own CLI
headlessly, so the reply is produced by a fresh process over the same
conversation rather than typed into the window on screen.

That second path needs the provider's CLI to be signed in on the computer, which
is separate from being signed in inside a desktop agent app — the CLI keeps its
own credentials. A reply of "not logged in" is the provider's own answer, passed
through unchanged; running `claude /login` once on that computer resolves it.

## Connection health

The header pill distinguishes **Offline** (this iPhone is not on the relay) from
**Mac offline** (the phone is linked, but the computer is not publishing). That
second verdict is driven by the computer's own lightweight heartbeat, not by how
old the chat catalog is: rebuilding a catalog reads every provider transcript and
can take far longer than a heartbeat interval, so catalog age alone declared
healthy computers dead and purged chats the phone was right to be showing. Both
signals must be stale before the link is reported offline, so a computer that
really did go away is still caught.

Heartbeat state is runtime-only and never persisted — after a relaunch the app
must see a real packet before it will call a computer Live again.

## Product and trust links

- Website: https://granttap.com
- Support: https://granttap.com/support
- Privacy: https://granttap.com/privacy
- Terms: https://granttap.com/terms
- Licenses: https://granttap.com/licenses
- Public MCP: https://github.com/sergii-ziborov/granttap-mcp
- npm: https://www.npmjs.com/package/granttap-mcp
- Public relay: https://github.com/sergii-ziborov/granttap-relay

The same links and install commands are available inside the iPhone/iPad app.

## Requirements

- Xcode with an iOS/iPadOS SDK that can deploy to 15.0 and a watchOS 10 SDK
- XcodeGen
- An Apple ID for signing
- An iPhone or iPad for main-app device testing
- A real paired iPhone and Apple Watch for WatchConnectivity and
  notification-mirroring tests; an iPad cannot replace the paired iPhone

Simulator covers pairing by high-entropy secure token, universal iPhone/iPad
navigation, localization, and the WatchConnectivity test seam. Compile and run
the universal app on both an iPhone and an iPad simulator. Mirrored actionable
Watch notifications must still be verified on real paired iPhone/Watch hardware.

## Generate and build

The generated `GrantTap.xcodeproj` and its shared schemes are committed so
Xcode Cloud can archive a fresh clone. Regenerate and commit the project after
changing `project.yml`:

```bash
brew install xcodegen
cd apps/ios
xcodegen generate
xcodebuild \
  -project GrantTap.xcodeproj \
  -scheme GrantTap \
  -destination 'generic/platform=iOS Simulator' \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  build
```

`project.yml` contains the product Team ID. Sign into that team in Xcode, then
run the `GrantTap` scheme for the universal iPhone/iPad app or
`GrantTapWatch` for the watch app.

For distribution, archive the `GrantTap` iOS scheme. Its **Embed Watch
Content** phase packages the modern single-target Watch app inside the iOS
archive; do not upload a separate watchOS archive.

## Install and pair the machine bridge

```bash
npm install -g granttap-mcp
granttap setup                 # Detect providers, configure hooks/helper, pair
granttap connect               # reuse pairing or show one encrypted QR
granttap setup                 # add/repair all detected agent adapters
granttap status                # honest provider/readiness check

# Install the public agent plugin from the GrantTap marketplace
codex plugin marketplace add sergii-ziborov/granttap-mcp
codex plugin add granttap@granttap

claude plugin marketplace add sergii-ziborov/granttap-mcp
claude plugin install granttap@granttap
```

There is one GrantTap helper and phone pairing per computer. Installing another
supported agent only requires `granttap setup`; it does not create a second
GrantTap installation or pairing. Use `granttap reset` before `granttap
connect` only for an explicit unlink-and-pair-again operation. Provider CLI
login remains separate.

### Exact-chat policy, without global UI clicks

GrantTap never searches all Cursor windows or presses arbitrary **Allow**,
**Continue**, or **Yes** buttons through Accessibility. Claude, Codex, and
Cursor decisions are correlated to an exact request and chat at their supported
hook boundaries. If a provider cannot enforce a capability deterministically,
the app shows that control as read-only instead of pretending it was disabled.

`granttap connect` uses the production zero-knowledge relay by default and prints a QR
plus a single-use code. Scan the QR from the iPhone/iPad pairing sheet, or use the
code in Simulator. Pass a different `wss://` URL to self-host.

The local Watch notification fixture remains available to development tests,
but it has no card or button in the shipping iPhone/iPad interface.

Real approvals are registered as native authenticated iOS notification actions.
Expand a banner or Notification Center row to use **Allow** or **Deny** without
opening GrantTap; iOS decides whether those actions fit in the compact banner.

## Apple capabilities — deliberately narrow

The universal iPhone/iPad target uses only capabilities required by shipping behavior:

- **Push Notifications** (`aps-environment`) for APNs device registration.
- **Background Modes → Remote notifications**
  (`UIBackgroundModes = remote-notification`) to retrieve queued encrypted
  envelopes after an APNs wake. Apple may delay or throttle background work;
  the UI and App Store copy must not promise instant silent delivery.
- **Time Sensitive Notifications** for approval requests. This is not Critical
  Alerts and does not bypass the user's notification settings.
- **LocalAuthentication** with a localized `NSFaceIDUsageDescription`. Face ID
  requires no extra entitlement; GrantTap receives only success/failure and
  falls back to the device passcode.

There is intentionally no Critical Alerts, PushKit/VoIP, background audio,
location, HealthKit, contacts, App Groups, or standalone watch networking
capability. The Watch companion receives mirrored notifications and synchronized
state through the paired iPhone. The iPad app has the main GrantTap features,
but does not act as an Apple Watch companion.

Before a signed device build, enable Push Notifications and Time Sensitive
Notifications on App ID `com.ziborov.granttap`, regenerate the provisioning
profiles for both app targets, and provision the relay's APNs authentication
key. An unsigned Simulator build validates Swift and plist shape but cannot
prove that a distribution profile contains the entitlements.

For a local device install, select the `GrantTap Local` scheme (`LocalTest`).
It signs with the development team and includes Push Notifications plus Time
Sensitive Notifications (`GrantTapLocal.entitlements`) so background APNs wakes
work on-device. Free Personal Teams still cannot obtain those capabilities —
use a paid team App ID with Push enabled, or the Debug/Release schemes.

## Security and privacy

- Pairing secrets are stored in the device-only Keychain.
- Older beta pairing data is migrated from UserDefaults and removed.
- Visible message and decision payloads are end-to-end encrypted.
- Hidden reasoning is not forwarded.
- APNs device tokens are never written to logs.
- APNs device tokens are stored only in the authenticated relay room for
  delivery and removed on unpairing or when APNs reports them stale.
- Delivery state, local task archives, scheduler history, and the audit log are
  bounded; phone-side files use iOS data protection.
- The bridge reports a bounded 90-day/160-chat metadata history separately from
  the 12-hour live-token window. Archived-chat details include tokens, context,
  MCP servers, skills, folder, branch, and model without deleting the Mac chat.
- MCP/skill usage is counted only from delivered explicit selections or
  structured tool-call metadata, including Codex calls nested inside its generic
  tool wrapper. Encrypted aggregate snapshots arrive even when a task is closed.
  Estimated context tokens cover tool arguments/results and are not separate billing.
- Notification task text can be hidden. Approval actions always require device
  authentication, and per-task encryption cannot be disabled in settings.
- The scheduler offers native recurrence controls plus an E2EE conversational
  planner backed by ephemeral read-only Codex or plan-only Claude Code turns.
  Its agent and workspace are explicit. New tasks default to a private GrantTap
  general workspace or one of the real folders previously opened by that agent,
  never the background helper's process directory.
- No advertising, cross-app tracking, or analytics SDK is present.
- `PrivacyInfo.xcprivacy` is included for both targets.

## Apple review materials

- [App Store metadata](AppStore/APP_STORE_METADATA.md)
- [Review notes](AppStore/APP_REVIEW_NOTES.md)
- [App Privacy answers](AppStore/APP_PRIVACY_ANSWERS.md)
- [Submission checklist](AppStore/SUBMISSION_CHECKLIST.md)
- [Localized screenshots](AppStore/Screenshots/README.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Architecture note

watchOS cannot maintain the product WebSocket independently. The iPhone owns
the live relay connection and synchronizes state through WatchConnectivity.
The watch can display synchronized state and initiate actions, but network
delivery requires the companion path. This limitation is stated explicitly in
the review notes and is not presented as standalone cloud connectivity.
