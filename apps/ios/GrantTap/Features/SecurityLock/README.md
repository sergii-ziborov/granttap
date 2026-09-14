# Security lock interface

These SwiftUI components render cold-start privacy chrome, explicit biometric
unlock, GrantTap PIN setup/entry, and the background privacy shield. Security
state and authentication live in `../SecurityAndAudit/SecurityGate.swift`.

Policy and PIN behavior are covered by `SecurityLockPolicyTests.swift` and
`SecurityPinTests.swift`.
