# Pending task continuations

Public entry: `AppModelTaskContinuation.swift`. A phone-created task registers
its creation ID with the receiver. Follow-ups and explicit queued messages can
then be encrypted and saved on the relay before a provider-native chat exists.
The receiver resolves the exact controller and original task before delivery.

`LocalTaskOrigins` preserves only routing IDs across phone restarts and outbox
pruning. Each queued row retains its own origin ID and immutable encrypted job
even after the visible chat adopts its native ID. Legacy stubs without an
origin registration retain their safe wait-for-remap behavior.

Tests live in `tests/`. Receiving computers need the origin-continuation protocol;
older receivers fail closed and cannot interpret a continuation as a new task.

## License

GrantTap’s commercial license applies. See the repository LICENSE.
