# Chat composer

Public entries: `ComposerField`, `ChatComposerDraft`, `ChatComposerDraftScope`.
The chat owns its draft reference without observing every keystroke. The composer
scope observes draft changes and updates its field, routing and send controls.
Typing does not invalidate the screen that owns the full message list. Sending,
queueing and dictation read and update the same retained draft.

`tests/ComposerDraftTests.swift` verifies that draft edits render the new text
inside the composer while the transcript owner is not rebuilt.

See the [engineering contract](../../../../../../../AGENTS.md).

`ComposerApprovalButton` opens the shared [chat approval choices](../Permissions/README.md)
directly beside attachments, preserving the same task rule as Task controls.
