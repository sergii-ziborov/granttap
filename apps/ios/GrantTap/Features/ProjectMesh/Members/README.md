# Company accounts and Project Mesh members

`CompanyAccount.swift` is the public entry point for repository grants. A company account has a stable local ID and either an explicit set of Engine repository IDs or an owner-selected `all` grant. It is not a device, a Git provider login, or a Mesh Project.

`MemberLink.swift` is the public entry point for device pairing and Mesh participation. Each link is one revocable pairing assigned to a company account. The owner can pair a phone or tablet before connecting a computer or sharing any Project; the link then has zero Mesh Project IDs and grants no Project data or action. The recipient scans its code in Settings → Connections. Later, the owner can grant selected Project IDs, a role, and action rules from that device's detail screen. One account may have several independently revocable device links. Linked and nested Projects keep their own Mesh IDs and must each be selected.

The owner's phone checks both grants before forwarding a complete Project snapshot, its key, chats, or actions. Because one Project snapshot can contain multiple repositories, a selected repository grant must cover every repository ID present in that snapshot. A newly discovered repository can make an existing share unavailable until the owner grants it. `all` includes later repositories. This gate is applied on the owner phone; it is not a GitHub or filesystem ACL. A recipient still needs its own provider and host permissions to read source code.

Existing device invites with no account ID retain their previous Project grants. The member detail screen marks them as legacy and lets the owner assign an account once. Assigning an account starts the repository gate immediately. Revoking or pausing an account stops new forwarding through this phone; already delivered data on a recipient device cannot be recalled. No account or Project name is used as authority in place of IDs and the authenticated pairing room.

The account store and device pairings are separate Keychain records. Changes are persisted before live routing is changed. Tests in `GrantTapTests/Features/ProjectMesh/Members` cover independent grants, two device links on one account, and revocation.

`ProjectControllerDevice.swift` presents the device viewing Members / Computers:
Mac Catalyst uses This Mac and a computer icon, iPad uses This iPad, and iPhone
uses This iPhone. The device label does not grant a Mesh key or change access.
The unit tests cover each device family and unknown devices; the shared UI test
verifies the visible label on iPhone and iPad.
