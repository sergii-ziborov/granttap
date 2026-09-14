# Human Attention

This module projects approvals, questions, failed delivery, and Project Mesh
decisions into one bounded `HumanAttentionItem` stream. The iPhone notification
layer and Apple Watch consume that stream directly, so a Mesh decision reaches
the wrist and the Lock Screen with the same identity and action semantics as an
ordinary approval. The iPhone Needs You list shows the same items through its
own task-row presentation.

Public implementation entry point: `HumanAttentionPipeline.swift`.

Repository quality and security rules: [`../../../../../AGENTS.md`](../../../../../AGENTS.md).
