# Capability execution evidence

[CapabilityExecutionUsageStore.swift](CapabilityExecutionUsageStore.swift) accepts summaries from the authenticated relay
room or the local Mac transport. `ProjectCapabilityUsage` matches them to exact
computer, provider, and execution links before displaying known use. Summaries
and recent call details have independent bounds; a missing detail does not erase
a recorded call. Configuration, permission, and installation are never usage.

Older MCP versions can omit summaries. Native history is preferred to transcript
previews, and unknown CPU or memory remains unknown. Clearing local usage rejects
older replayed summaries. The relay can replay the encrypted usage status when
the computer is unavailable. Tests live in the corresponding feature tests.

See the [engineering contract](../../../../../../AGENTS.md) for quality and
publication requirements.
