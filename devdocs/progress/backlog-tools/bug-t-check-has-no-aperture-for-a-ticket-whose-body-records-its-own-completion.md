
## Third live instance, 2026-09-02 — found while dispatching, not while auditing

`bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string` sat at
`status: backlog`, **prio 70, second in `ready --track P`**, while its fix had
been on origin since 02:03 that morning (`9c6b216aa`, 14 assertions added). Its
own summary ended *"Fixed by teaching the oracle AN_FIELD and AN_DEREF"* — past
tense, in the one field everybody reads — and a SECOND ticket
(`regression-lib-test-lib-synapse-3`) named it as the thing that fixed them.

**Two independent documents said it was done and the ranker kept offering it.**

Cost this time: it was about to be handed to an agent as work. The previous two
instances cost a dispatch each; this one was caught only because the coordinator
happened to read the queue before relaying it, which is not a mechanism.

Note the aperture would not even need prose analysis here — a ticket whose
summary contains "Fixed by" while its status is `backlog` is a one-line grep.
That is not the general case, but it is a cheap first cut that would have caught
all three.
