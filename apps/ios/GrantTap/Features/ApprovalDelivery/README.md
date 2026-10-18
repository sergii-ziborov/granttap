# Approval delivery

Explicit Allow/Deny decisions are persisted before sending, protected on the
device and scoped to the exact request, session and authenticated computer.
Failed writes remain queued and retry to the relay even while the computer is
offline. Retries preserve the original 15-minute lifetime, request, session and
room. Matching terminal coverage, resolved/cancel messages and explicit unlink
remove the decision. Only a durable relay receipt changes the UI to saved; the
computer independently checks the still-live native gate before applying it.
Relay storage does not mean permission was applied. Cache clearing preserves this outbox.
Tapping a card opens its action details. Per-chat automation is a separate,
explicit Apply operation bound to the current computer epoch and Project policy
revision. The UI shows it as applied only after that computer confirms the
matching operation and effective rule; rejection or timeout restores the prior
confirmed state. A chat control never resumes global automation or overrides a
Project deny.

Claude's structured questions retain the complete set of options, multiple
selection and a custom answer. They require answers to every question and do
not offer Auto allow. The durable decision outbox also stores those answers;
Watch opens the phone for the form instead of sending a generic permission tap.
The custom-answer editor has a keyboard Done action, so the next question and
submit control remain reachable on smaller iPhones without discarding the draft.
