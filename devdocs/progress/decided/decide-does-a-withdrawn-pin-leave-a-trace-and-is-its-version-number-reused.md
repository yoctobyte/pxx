---
slug: decide-does-a-withdrawn-pin-leave-a-trace-and-is-its-version-number-reused
title: "Does a withdrawn pin leave a trace in the ledger, and is its version number reused?"
track: U
prio: 60
type: decide
status: decided
owner: ""
created: 2026-08-30
found-by: frankD (auditing the launch draft's fact sheet), verified by frank-coordinator
summary: "RULED 2026-08-31 by the owner on the REUSE fork: DO NOT REUSE a withdrawn version number -- burn it. 'skipping is safe, there is nothing to gain with reusing apart confusion.' So no number ever names two binaries and "measured at v394" is always resolvable. The TRACE fork (erase vs annotate) was NOT separately ruled, and burning the counter forces it: a gap in the sequence is itself a question. Recommendation, explicitly not the owner's word: keep erasing from pin.log (what is in force), append a one-line withdrawn row to history.log (what was ever blessed) -- the two files already split those two questions. This also repairs a public claim: the launch fact sheet says pins are reconstructible, true of git and false of the ledger a reader would check."
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
one was **in force for ten minutes** (05:27:09 -> 05:37:35), other lanes built against it,
and tickets cite it.

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

# Correction to this ticket's own first draft

It said the withdrawn pin was in force for **36 minutes**. Wrong, and caught by frankD against
the commit timestamps: `cc5e02d6c` 05:27:09 -> `b8fd07377` 05:37:35 is **ten minutes**. The 36 is
`b8fd07377` -> `d58eb5d92` 06:13:00, the gap from the revert to the replacement, which is a
different interval and a less alarming one. **The window in which a lane could have built against
the withdrawn binary is the ten minutes.** Recorded rather than silently edited because it is a
number that was headed for launch copy.

# The argument that settles it (frankD)

Reuse is not merely ambiguous going forward. **It retroactively falsifies sentences already
written, and it does so silently.**

`feature-lib-tkinter-grid-pad-accepts-a-two-tuple` (in `done/`) carries the heading
**"2026-08-30 — CLOSED against the pin. v394 carries the fix."** That was true when written. It
is false now. **Nothing in the ticket changed.** The reader has no way to know which v394 the
sentence meant — which is face 188's shape: *unfalsifiable* rather than merely wrong.

Burning the counter costs a gap in a sequence nobody reads sequentially. Reuse costs the truth
value of every prior citation.

**The partial mitigation, and it is the argument for a convention rather than only a tool:** that
same ticket also writes the **sha** — `v394 e2ea9034a65ea8b6` at line 360 — so a careful reader
can disambiguate. The heading cannot. **A version number alone is the hazard; a version number
next to its sha is not.** Whatever is decided about the ledger, "cite the sha, never the version
alone" is worth stating as a rule, because it degrades gracefully under either outcome.

**And a third stale number was found in the same file**, unfixed here deliberately: its banner
says the pin was blessed *"at ~06:40"*. It was 05:27:09; 06:13:00 is when the *replacement* was
pinned. It sits in `done/`, and this repo's rule is that a session record is not rewritten — but
it is evidence of how fast an unanchored time propagates, and Track D should not cite it.

---

# RULED 2026-08-31 - burn the counter

Owner, on the reuse fork, in full: *"about the pin numbering - i would recommend
against re-using. skipping is safe, there is nothing to gain with reusing apart
confusion."*

**So a withdrawn version number is never issued again.** `make revert` may take a
pin out of force, but the counter does not roll back. No number ever names two
different binaries, and a worker citing "measured at v394" has written something
resolvable.

That is the fork that mattered. The hazard was never that a withdrawn pin is
forgotten - it is that **a version number naming two binaries is a claim which
reads as checked and is not**, the same family as the registers this fleet worked
through on 2026-08-29/30.

## The trace fork - NOT ruled by the owner, recommendation only

Burning the counter does not settle erase-vs-annotate; it **forces** the
question, because a gap is itself something a reader will ask about. Someone
hitting v393 -> v395 with nothing between learns only that something is missing.

Recommended, and marked as mine rather than his: keep erasing from `pin.log`
(which answers *what is in force*) and append a one-line `withdrawn` row to
`history.log` (which answers *what was ever blessed*). The two files already
split those two questions. One line of explanation once, against a re-derivation
every time someone hits the gap.

**Do not implement the trace half on this ticket's authority.** Implement the
counter half, which is ruled. If the annotation turns out to be more than a
one-line append, put it in front of the owner first.

## The public claim this repairs

The launch fact sheet says pins are in git with their sha256 and landing commit
*"so the trajectory is reconstructible"*. True of git; false of the ledger a
reader would actually check, since `history.log` and `pin.log` had the row
deleted. Burning the counter makes the ledger non-contradictory; the `withdrawn`
row would make it complete. Until then that sentence is accurate about git and
should not be widened.

*Ruled 2026-08-31 by the owner; trace half left open, deliberately.*
