# Demo support

This module contains deterministic DEBUG-only data used by screenshot and UI
tests. `AppModelDemo.swift` owns lifecycle changes; `AppModelDemoFixtures.swift`
owns the sample catalog, activities, approvals, and schedules.

The module is compiled into Debug and LocalTest only because all fixture symbols
are enclosed by `#if DEBUG`. Release builds keep only `stopDemo()`, which clears
possible developer residue after connection recovery.
