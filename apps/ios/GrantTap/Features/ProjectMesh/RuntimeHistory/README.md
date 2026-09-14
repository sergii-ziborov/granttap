# Runtime History

`ProjectInvocationModels.swift` is the public phone wire projection of the
Engine-owned, content-free Invocation journal. `AppModelRuntimeHistory.swift`
requests bounded pages under the Project E2EE key. `TaskRuntimeHistoryView.swift`
shows reported tool outcomes, explicit gaps and verified file evidence inside
the existing Task screen. The phone never persists this projection as plaintext.

A request or a reported success is not a confirmed filesystem change. Only a
`change_observed` event with repository, revision and content hash may be shown
as verified. When an Engine is unavailable, the UI says so rather than inferring
history from the small Usage buffer.
