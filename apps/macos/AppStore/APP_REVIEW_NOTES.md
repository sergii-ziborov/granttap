# Mac review notes

GrantTap is a native Mac Catalyst controller for coding agents on the user's
computer. It does not include an AI model or transmit provider model traffic
through its relay. The separate open-source MCP runs outside the app sandbox.
The app accesses it through an authenticated loopback connection after explicit
local authorization; it does not download or execute helper code in its sandbox.
A user who has not installed the MCP receives installation guidance.

## Inspection without a connected computer

1. Open GrantTap → About GrantTap to see version, product scope, developer,
   third-party notices and license information inside the main window.
2. Open Help → GrantTap Help to read the connection and purchase guides.
3. In Settings, open Terms, Privacy, Licenses and Pricing. These documents are
   included in English and Russian and can be read without a network connection.
4. Open Settings → Mac license. The non-consumable Mac purchase and Restore
   Purchases use StoreKit. Personal is optional and is purchased separately.

## Connected local control

Install the documented MCP from https://github.com/sergii-ziborov/granttap-mcp
on the review Mac, start it, and authorize the local GrantTap client. An actual
provider chat needs the reviewer's own supported coding-provider installation
and account. GrantTap provides neither provider credentials nor AI credits.
Use a dedicated test chat and repository for approvals and file operations.

Settings → Device network can connect iPhone/iPad with a single-use QR or
connect a computer by link. Existing pairings are preserved when adding a device.
Direct mode discovers an encrypted endpoint address; the user must supply a
reachable TLS endpoint or VPN. Fully self-hosted mode uses the user's relay;
managed delivery and supported APNs wake-up are optional Personal services.

The Mac license persists after cancelling Personal. A refunded or revoked Mac
purchase removes that license. Tier limits count computers, not coding agents.
Subscription trial eligibility and regional prices follow Apple's purchase sheet.
Apple Watch uses its paired iPhone and is not a standalone Mac companion.

Support: https://granttap.com/support; sergii.ziborov@gmail.com.
Before submission, add the exact signed build, sanitized release screenshots,
verified account contact, and any review-specific access details in App Store
Connect. Do not place real user's pairing tokens, chats or provider credentials
in review notes or screenshots.
