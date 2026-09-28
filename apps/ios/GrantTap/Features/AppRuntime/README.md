# App runtime

These extensions split the phone runtime by lifecycle: linked-computer
registry, room routing, approval convergence, agent events, outbox admission,
retry/completion, catalog persistence, activity, and relay session queues.

The root `AppModel` retains observable state and startup only. Runtime
regressions are covered by `GrantTapTests/AppRuntimeTests.swift` and the full
real-Simulator XCTest suite.

`SessionActivityTelemetry` preserves received per-call capability measurements
when a later page omits them. It retains evidence only for the same tool and
capability, replaces explicit new measurements, and never combines different
sampling windows. `CommandTelemetryRetentionTests` exercises this through
activity merging and the persisted wire round trip.
