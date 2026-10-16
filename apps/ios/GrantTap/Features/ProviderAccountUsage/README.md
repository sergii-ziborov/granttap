# Provider account usage

Public entry: `ProviderUsageSection` for Usage and `ProviderAccountUsageRows` for
the existing model picker. Both Apple clients use the same optional encrypted
Mesh contract (`ProjectEndpointModelCatalog.accountUsage`).

Each report stays scoped to its computer, provider and limit bucket. Repeated
Project reports collapse to their latest observation. Missing windows remain
unknown. Reports older than five minutes and expired windows show Update needed;
they never reset themselves to an invented 100% allowance. Subscription limits
are separate from retained session token and tool statistics.

Codex reports through its installed account API. Other providers display native
reports where available, and explicitly show missing subscription evidence.
Tests live in `tests/ProviderAccountUsageTests.swift`.
