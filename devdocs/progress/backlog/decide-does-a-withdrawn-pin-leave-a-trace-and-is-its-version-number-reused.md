---
slug: decide-does-a-withdrawn-pin-leave-a-trace-and-is-its-version-number-reused
title: "Does a withdrawn pin leave a trace in the ledger, and is its version number reused?"
track: U
prio: 60
type: decide
status: backlog
owner: ""
created: 2026-08-30
found-by: frankD (auditing the launch draft's fact sheet), verified by frank-coordinator
summary: "make revert DELETES the row from history.log and pin.log, and the next pin REUSES the counter -- so v394 names two different binaries and the withdrawn one appears nowhere in the ledger. Two forks: erase vs annotate, and reuse vs burn. It touches a public claim: the launch fact sheet says pins are in git with their sha256 and landing commit 'so the trajectory is reconstructible', which is true of git and false of the ledger a reader would actually check."
---

# What happened, measured

The coordinator blessed and withdrew a pin on 2026-08-30. All three commits are on
`origin/master`:

```
cc5e02d6c 05:27  chore(stable): pin v394 e2ea9034a65ea8b6
b8fd07377 05:37  chore(stable): revert pin v394 -> v393, it breaks Track B's gate
d58eb5d92 06:13  chore(stable): pin v394 53800fbeb0b66e11
```

`b8fd07377`'s diffstat carries the mechanism: **`history.log | 1 -`** and **`pin.log | 1 -`**.
The revert **deleted the row** rather than appending a withdrawal. `d58eb5d92` then **reused the
counter**.

Net effect today: `grep e2ea9034 stable_linux_amd64/` returns nothing, `history.log` holds exactly
one v394 row, and **`v394` names two different binaries** in this repo's history. The withdrawn
one was in force for 36 minutes, other lanes built against it, and tickets cite it.

# Why this is a decision and not a bug

Both behaviours are coherent; they answer different questions, and the ledger cannot answer both
without saying which it is.

| | **erase** (today) | **annotate** |
| --- | --- | --- |
| the ledger is | a record of pins **in force** | a record of pins **blessed** |
| "what was pinned on 08-30?" | one answer, always current | two rows, one marked withdrawn |
| a citation of a withdrawn sha | resolves to nothing | resolves, marked |
| cost | history recoverable only via `git log -p` | the ledger carries states nobody should build on |

And separately:

| | **reuse the counter** (today) | **burn it** |
| --- | --- | --- |
| `v394` means | two binaries | one binary, ever |
| cost | a version number is not an identifier | gaps in the sequence |

# It touches a public claim, which is why it is ranked rather than parked

The launch draft's fact sheet says pins are *"in git with their sha256 and their landing commit,
so the trajectory is reconstructible — that is the claim worth making, not the count."*

**True of git, false of the ledger.** The row *is* recoverable — `git log -p --
stable_linux_amd64/default/history.log` finds it. But nobody reconstructs a pin trajectory by
running `log -p` on a log file; they read the log file, find one v394 row, and have no way to
learn a different v394 existed. That is precisely the failure mode CLAUDE.md's claims-discipline
section describes: **write public claims uncompressed, because the qualifying words carry the
distinction and terse styles drop them first.** "Reconstructible" compressed away *from what*.

**Track D is fixing the draft to describe the ledger AS IT IS**, not waiting on this decision — a
draft describing an intended future state is the same defect one level up. If the decision changes
the ledger, the draft changes with it.

# Recommendation (coordinator): annotate, and burn the counter

Not because erasing is indefensible — a ledger of what is in force is a reasonable thing to want —
but because **a version number that names two binaries is a claim that reads as checked and is
not**, which is the exact hazard this fleet spent 2026-08-29/30 finding in six other registers
(faces 213, 215, 218, 219). A worker citing "measured at v394" today has written something
unresolvable, and nothing warns them. The gap in the sequence costs a line of explanation once;
the ambiguity costs a re-derivation every time someone hits it.

Cheapest form if the full change is not wanted: keep erasing from `pin.log` (in force) and
**append a `withdrawn` row to `history.log`** (blessed), which already reads as the historical
record. That splits the two questions along the two files that already exist.

# Not decided here

Whether `make revert` should also refuse to reuse a counter mechanically, or merely record it, is
implementation and belongs to Track A once the fork is settled.
