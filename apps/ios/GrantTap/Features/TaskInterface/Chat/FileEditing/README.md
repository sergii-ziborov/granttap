# File edit requests

Public entries: `TaskFileEditRequest` and AppModel's `queueTaskFileEdit`.
The workspace preview supplies the original UTF-8 text. A proposed edit goes to
the same Task through the existing durable encrypted queue as a user request,
with the original, replacement and their SHA-256 hashes in a JSON attachment.
The computer's agent checks the original against the current file before applying
changes under the Task's existing permissions. No client or relay writes the file.

Only complete text previews up to 128 KiB can be edited. Partial and binary files
remain readable where supported. Sending preserves the queue's model, Effort,
offline retry, transfer guard and confirmed relay status behavior.

Feature tests live in `GrantTapTests/Features/TaskInterface/FileEditing`.
See the repository [engineering index](../../../../../../../AGENTS.md) and
the workspace reader's public entry `../FileReview/AppModelTaskWorkspace.swift`.

`TaskFileEditSession` belongs to the Files presenter. It retains the exact draft
when UIKit recreates a nested file controller. Preview and editor share one
navigation container; dismissing unsent changes requires an explicit choice.
