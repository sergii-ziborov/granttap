# Knowledge

Bounded Project knowledge presentation backed by source-labelled Engine Memory,
Task capsules, and invocation history. A newer same-scope record can supersede
an earlier decision; merging an old phone snapshot does not make that earlier
record current again while the correction remains in the bounded projection.
The Engine journal retains the audit history. This view is not the canonical
memory store or a claim that missing history is empty.

The decision editor submits a statement for an existing Project Task to one
Live bound computer. The computer records it through Engine Memory before the
phone shows `recorded`. Corrections use `supersedesRecordId` and keep the old
record in the audit history. A lost reply can be retried with the same record
identity while the request is fresh; after that, the phone reports unknown
status and asks the person to inspect Knowledge before entering it again.
Chat titles are never imported as verified decisions.

`ProjectKnowledgeRefresh` refreshes the selected Mesh snapshot and invocation
tails on entry, reconnection, and explicit refresh. An already loaded tail is
queried again. The header distinguishes refreshing, fresh evidence and a failed
refresh while keeping saved records visible; the timestamp is explicitly the
snapshot generation time. Queries expire after 15 seconds and late generations
cannot overwrite a newer request. Structured Task completion reports remain
visible with Agent report attribution while Engine Memory backfill is pending.
No chat text is promoted automatically to a decision or verified result.
