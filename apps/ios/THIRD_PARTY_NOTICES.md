# Third-party notices

GrantTap for Mac, iPhone, iPad, and Apple Watch includes or interoperates with the
following components. The Apple app bundles the full original notices for
TweetNacl SwiftWrap 1.1.0 and Three.js r160 in About → Third-party notices,
readable offline. Three.js is used only by the Mac graph viewer. The separate
MCP and Engine distributions carry their own full versioned notices. Their
source access does not grant rights to reserved first-party components.

| Component | Purpose | License | Source |
| --- | --- | --- | --- |
| TweetNacl SwiftWrap | NaCl authenticated encryption on Apple platforms | MIT | https://github.com/bitmark-inc/tweetnacl-swiftwrap |
| tweetnacl-js | Compatible machine-side NaCl implementation | Unlicense | https://github.com/dchest/tweetnacl-js |
| Model Context Protocol TypeScript SDK | Public MCP server | MIT | https://github.com/modelcontextprotocol/typescript-sdk |
| ws | Machine-side WebSocket client | MIT | https://github.com/websockets/ws |
| Zod | Protocol validation | MIT | https://github.com/colinhacks/zod |
| QRCode | Terminal pairing QR generation | MIT | https://github.com/soldair/node-qrcode |
| Weavatrix Rust | Local repository evidence and graph analysis in the separate Engine | MIT | https://github.com/Weavatrix/weavatrix-rust |
| Cortex Context | Bounded context compilation in the separate Engine | MIT OR Apache-2.0 | https://github.com/sergii-ziborov/cortex-loom/tree/main/crates/cortex-context |
| Three.js r160 | Local Repo Lens Cyberboard graph on Mac | MIT | https://github.com/mrdoob/three.js |

The separate Engine also integrates `cortex-weavatrix`, an unpublished
first-party Cortex Loom adapter with reserved rights. Weavatrix Loom is a
distinct ecosystem project and is not bundled in the Apple apps. These
entries identify package boundaries; binary distributions must include the
notices for the exact versions they contain.

GrantTap, its iPhone app, and its Apple Watch app are independent products.
Apple, Apple Watch, iPhone, and App Store are trademarks of Apple Inc. Claude
and Claude Code are trademarks of Anthropic. OpenAI and Codex are trademarks
of OpenAI. GrantTap is not affiliated with or endorsed by those companies.

## Optional external SweepLoom CLI

The Mac provider-storage inspector can use a separately installed
[SweepLoom CLI](https://github.com/Weavatrix/sweeploom), licensed under MPL-2.0.
It requests storage and process metadata through SweepLoom’s MCP interface.
SweepLoom code and its executable are not bundled in the Apple application;
its installation retains the upstream license. GrantTap’s confirmed cache
cleanup moves selected temporary files to the Mac Trash.

## Distribution boundaries

Apple system frameworks are supplied under Apple platform terms. The Apple
apps do not bundle the Node runtime dependencies or the separate Engine binary.
The helper and Engine retain their own dependency notices. Commercial GrantTap
terms apply to first-party software and do not replace MIT, Apache, Unicode,
Unlicense or other upstream grants. Current license summaries and full website
dependency notices are available at https://granttap.com/licenses.

The first-party Repo Lens Cyberboard renderer is incorporated under the explicit
GrantTap commercial grant in `apps/macos/GraphWeb/REPO_LENS_LICENSE.txt`. It is
not represented as MIT software; its Three.js dependency remains MIT.
