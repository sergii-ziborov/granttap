# Local MCP on Mac

`MacLocalMCPModel` is the Apple-client entry point for the installed GrantTap MCP.
It discovers the loopback status endpoint and uses the authenticated native
desktop bridge for bounded Mesh, Task, conversation, image, usage, and capability
operations. The MCP forwards those operations to its same-user Unix socket.
The machine runtime remains in the sibling `granttap-mcp` repository.
Local Mac Task handoff uses `desktop.task_handoff` through that authenticated
socket. The MCP checks the exact local Task owner before preparing the encrypted
capsule. The Mac app displays a rejected or unavailable handoff on the sheet.

The Mac **Devices** tab uses the same passkey Account Mesh as iPhone and iPad.
Signing in creates or joins the account even before an MCP or computer is
available. When a local MCP appears, the Mac client offers to link it to the
signed-in account and retries that link; the helper keeps its existing machine
identity when already linked. The account may include many computers and
Project Meshes, but each Task retains an explicit computer route. The MCP
reports the Mac's user-assigned Computer Name for display, while stable machine
identity remains separate. A Mac App Store build cannot install a global helper
into the user's home directory, so the install control opens the helper setup
instructions; runtime code is not duplicated inside this Apple client.

`MacLocalMCPPolicy` validates status, acknowledgement, and rejection payloads,
preserves policy drafts, and applies revisions through the canonical runtime.
`MacLocalMCPApproval` reads the actual Mesh auto-accept value and writes only the
selected Mesh. Local observations use the `local-mac` usage source without adding
that source to relay routing.

Usage includes provider-reported token facts keyed by native session and provider.
`SessionUsageSnapshot` enriches only executions on the discovered local endpoint;
it preserves Task, Project and computer identity. Counts and period rollups live
in `CapabilityUsage`; tool-list filters do not change the overview.

The Mac shell keeps the native window controls and places the brand above the
navigation stack in normal layout, so pushing a detail cannot move the header.
Local MCP discovery belongs to startup; computer-network pairing belongs to
Settings. Tests for the shared policy and usage behavior are under
`GrantTapTests/Features/ProjectMesh`; runtime validation tests belong to the MCP.
Shared usage regressions also live in `GrantTapTests/Features/CapabilityUsage`.

Settings offers **Connect iPhone or iPad**, displaying a separate one-use QR
from the local MCP, and **Connect a computer by link**, adding another computer
through its encrypted mailbox, or importing the device-network invitation
from an iPhone as one atomic registry update. Existing connections are retained. Enrollment
completes when that new device is observed; saving a computer link does not
claim that it is online. Codes remain in memory and disappear on expiry or
completion.

`DesktopCatalogSources` combines local observations with authenticated computer
catalogs. `MacCatalogRouting` checks Project, Task, provider, native session and
computer before choosing the local desktop bridge. Refreshing one computer cannot
replace another computer's list. Tests are in
`GrantTapTests/Features/MacLocalMCP` and `GrantTapTests/Features/Pairing`.

See [`AGENTS.md`](../../../../../AGENTS.md) for the repository contract.

Generated image references are advertised by the exact Task conversation and
fetched with `desktop.task_image`. The client never reads provider transcripts
or arbitrary local paths. Native messages retain up to 16,384 UTF-16 units;
the runtime also bounds the whole response to fit the socket frame.

The existing refresh loop reads `desktop.live_catalog` every five seconds when
MCP is ready. `MacLiveSessionProjection` checks the exact Project, Task, native
session, provider, computer and current owner before applying its live state
and progress to Now. A fresh native turn can supersede an older closure in the
presentation; it does not rewrite durable Execution history or handoff rights.
Completed Tasks and former owners are excluded. Reports expire after one minute.

The existing This Mac Settings section includes Codex hook review.
`MacLocalProviderHooks.swift` carries a displayed hook approval through the
authenticated desktop bridge and decodes its correlated native confirmation.
Status discovery and refresh never approve hooks. The review screen and model
validation are shared with iPhone/iPad under ConnectionHealth.

`MacLocalAttachmentBatch` prepares bounded private file copies for local Task
sends and creation. Only the small path/name/MIME manifest travels over the
authenticated desktop bridge. The MCP validates and reads the batch and passes it through
the existing provider attachment pipeline. Copies are removed after the request
or any error. Source picker files and unrelated directories are untouched.

## Provider storage

`MacProviderStorageView` uses `desktop.provider_storage` on the authenticated
same-user desktop channel. The runtime inspects Codex, Claude and Cursor metadata
through the separately installed SweepLoom CLI. The app does not bundle SweepLoom
or execute a second machine runtime. A human selects at most 16 regenerable cache
or log entries and confirms moving them to the Mac Trash. Provider conversations,
secrets, databases, rules and skills remain inspect-only. Running providers,
symlinks, capped scans, expired reviews and modified cache trees block cleanup.

The separate runtime supports the normal SweepLoom CLI locations or
`GRANTTAP_SWEEPLOOM_PATH`. No scanning or cleanup runs automatically at app launch.

Fresh local observations replace older relay copies only for the same native
session, provider and computer. A different computer or provider keeps its
separate routing, and an older local observation cannot overwrite newer state.

The visible Mesh insight views read local process samples and selected graph
reports every ten seconds. `MacLocalMachineLoad` validates bounded, nonnegative
measurements and preserves native chat attribution when converting to the shared
wire model. Periodic lightweight catalog updates retain graph enrichment without
requiring a Cortex report. Historical command measurements remain separate from
live process readings. Native active chats also receive provider usage facts,
without replacing fresher native totals with an older cached scan.
