---
slug: decide-pchar-node-side-storage-or-a-pchar-type-kind
title: "PChar recognition: a tyPChar kind like WideChar got, or node-side storage — or neither, now that the walk is one function?"
track: U
prio: 40
type: decide
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "The last thing owed by refactor-centralize-managed-string-pchar-conversion is slice 3, and its premise expired twice. WideChar got a real type kind (tyWideChar) and no longer wants node-side storage; PChar cannot copy that, because a PChar's pointee VARIES and a kind per pointee does not scale. Meanwhile the deref walk is now ONE function and 198/198 cross-product rows match fpc, so the third option — do nothing structural and keep extending the one walk — is live. This is a design call, not work."
---

# The fork

`refactor-centralize-managed-string-pchar-conversion` closed with slices 1 and
2 delivered and slice 3 reading *"fold WideChar in — same treatment"*. That
sentence is now wrong twice over, and what replaces it is a genuine design
choice rather than a task.

**Option A — a `tyPChar` type kind**, mirroring what `tyWideChar` (kind 31) and
`tyUCS4Char` did. A kind survives assignment through a variable, which is the
one thing a node side-channel cannot do, and `WriteLn` becomes trivially
correct because it can dispatch on the kind instead of guessing.
*Against:* a PChar's pointee VARIES — `PWideChar`, `PByte`, `PInteger`,
`^PChar` — and a kind per pointee does not scale. `tyWideChar` worked precisely
because WideChar is ONE type; PChar is a family. A `tyPChar` that means only
"pointer to 8-bit char, depth 1" would leave `^PChar` and `PPChar` exactly where
they are now, i.e. answered by the depth/base triple, so the repo would carry
BOTH mechanisms for one concept.

**Option B — node-side storage at creation**, C's `cparser.inc` pattern: compute
the pointer shape once when the node is built and store it, readers do a lookup.
*Against:* measured twice in this ticket's history, the storage ALREADY EXISTS —
the deref chain has been stamping (remaining depth, base kind, base rec) onto
every `AN_DEREF` all along, and both times the fix was to make a reader look
rather than to add a field. A third parallel array is the shape the ticket's own
text rules out.

**Option C — declare it structurally done.** The four copies of the deref walk
are now one (`ResolveDerefShape`), the metadata is populated at the declaration
sites, and the acceptance cross product is **198/198 identical to fpc 3.2.2**
(88 rows of source-shape x context, plus 110 more with new shapes). Under C,
future PChar shapes are one arm in one function, which is what the consolidation
bought, and no new mechanism is introduced.

# Recommendation

**C, with A held in reserve for one specific symptom.** The argument for a kind
was always `WriteLn`, the context that cannot guess — and PChar has no `WriteLn`
gap left: `WriteLn(p)`, `WriteLn(q^)`, `WriteLn(qa[0]^)` and `WriteLn((qa[0])^)`
all print the text today. So the motivating symptom is absent, and adding a kind
would be paying `defs.inc` numbering churn (a shared-file change every frontend
sees) for a problem that is not currently observable.

Revisit A only if a shape appears where the char-ness must survive a plain
assignment through a variable that the triple cannot describe. Note that would
be a real finding, not a hypothetical: it is exactly the case node metadata
loses and a kind keeps.

# What resolving this unblocks

Nothing is waiting on it — the ticket is resolved and the code is green. This
exists so the next person to read *"slice 3, still owed"* does not implement a
`tyPChar` on the strength of "do what WideChar did", which is the obvious and
probably wrong instinct, and which the ticket already says out loud.
