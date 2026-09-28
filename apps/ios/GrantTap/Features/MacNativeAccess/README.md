# Native Mac access

Mac App Store builds use the MCP's authenticated loopback desktop bridge instead
of reading machine-private Unix sockets outside App Sandbox. A local browser
consent session uses S256 PKCE and a fixed native callback; no website or phone
is required. The token is kept in the device-only Keychain and is not a provider
credential. Only existing desktop operations are forwarded. HTTP redirects are
refused, requests and responses are capped at 512 KB. Debug builds keep the
same-user private socket for explicit source evaluation, with no automatic demo.
