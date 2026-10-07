# Native Mac access

Mac App Store builds use the MCP's authenticated loopback desktop bridge instead
of reading machine-private Unix sockets outside App Sandbox. A local browser
consent session uses S256 PKCE and a fixed native callback; no website or phone
is required. The token is kept in the device-only Keychain and is not a provider
credential. Only existing desktop operations are forwarded. HTTP redirects are
refused, requests and responses are capped at 512 KB. Signed Mac builds,
including the local test configuration, always use this bridge.

When the app is signed in to an Account Mesh, it can exchange that account's
passkey session with the local MCP for the same scoped desktop grant. The MCP
verifies the account and machine link with granttap.com before issuing the
grant. This recovers local access when the MCP was linked through its own
passkey flow. If that exchange fails, the app opens local browser consent so a
stale account session cannot block access to this Mac.
