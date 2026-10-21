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

`TaskComposerStopButton` carries an indeterminate ring for a working Task with
a Live route (or the local Mac runtime). Pending pause has its own spinner;
offline work has no moving activity ring. Reduce Motion keeps a static arc,
and VoiceOver reads the working/connection/pausing state without announcing
an invented progress percentage.
