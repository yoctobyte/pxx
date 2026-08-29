---
slug: bug-t-a-reopened-fuzz-finding-erases-the-history-that-makes-it-useful
title: "A reopened fuzz finding overwrites first_seed/first_sha/opened and DELETES fixed/fixed_sha - the reopen flag survives, the facts about it do not"
track: T
type: bug
prio: 45
blocked-by: []
status: done
found: 2026-08-29
found-by: frank-coordinator
owner: pxx-a5
---

# A reopened fuzz finding erases the history that makes it useful

- **Type:** bug (Track T - the fuzz ledger, `devdocs/progress/tstate/fuzz/LEDGER.json`)
- **Found:** 2026-08-29, reading `ec2f50d8c` during a coordinator tick.
- **Severity:** the instance is harmless; **the mechanism is not.**

## Measured - the same entry, before and after one reopen

`fpc-self_if` was found on borg 2026-07-14, marked fixed 2026-08-16, and
re-appeared on plexus 2026-08-29. Diffing its ledger entry across that reopen:

| field | before the reopen | after | |
| --- | --- | --- | --- |
| `first_seed` | `27295` | `91108` | **overwritten** |
| `first_sha` | `dbbcc912715f` | `eb1b200ee92f` | **overwritten** |
| `opened` | `2026-07-14T17:41:07Z` | `2026-08-29T03:54:33Z` | **overwritten** |
| `fixed` | `2026-08-16T12:05:05Z` | *absent* | **deleted** |
| `fixed_sha` | `42e147157b60` | *absent* | **deleted** |
| `hits` | `1` | `1` | not incremented |
| `examples` | `[(27295, dbbcc912715f)]` | `[(91108, eb1b200ee92f)]` | **replaced** |
| `reopened_from_fixed` | `False` | `True` | the one honest field |

So after a reopen, **`first_*` does not mean first** - it means *first since the
most recent reopen* - and `opened` does not mean opened. Nothing in the entry says
so.

## Why this is the expensive shape and not a tidiness complaint

`reopened_from_fixed: True` records **that** the event happened and destroys
**every fact about it.** A flag that survives while its evidence is deleted is
worse than no flag: it tells a reader there is a history and gives them nothing to
read, so the natural next step - "when was it fixed, and what reopened it?" - has
no answer in the file that just claimed the event.

The concrete loss here is a **bisect bracket.** `fixed_sha=42e147157b60` and the
reopening sha `eb1b200ee92f` together bound the window in which the finding came
back. That pair is exactly what a regression hunt starts from, and the ledger held
both, one at a time, and now holds neither.

**This instance is harmless and that is the trap.** `fpc-self_if` is FPC
contradicting itself between `-O0` and `-O2`; the note says so and pxx agrees with
`fpc-O0` at all three levels, so *"pxx is not involved"* and no bisect was ever
wanted. **The erasure is generic - it will behave identically on a pxx-side
finding**, where the bracket is the whole value. The mechanism was observed on the
one class of finding whose loss costs nothing, which is why it has survived since
at least the 2026-07-14 entry.

Related, and probably the same fix: the commit subject reads **`NEW: fpc-self_if`**
for a signature the ledger itself knows is a reopen. `NEW` is a word people grep
for and act on. A reopen is arguably more interesting than a first sighting - it
means something that was fixed came back - and it is currently reported in the
vocabulary of a first sighting.

## Direction

Preserve on reopen rather than replace: keep `first_seed`/`first_sha`/`opened` as
the **original** discovery, append to `examples` instead of replacing, increment
`hits`, and retain `fixed`/`fixed_sha` as history (a `reopens: [{fixed_sha,
reopened_sha, at}]` list keeps the bracket explicit). Then say `REOPENED` rather
than `NEW` in the subject line when `reopened_from_fixed` is set.

**Not measured, and worth one check before building:** whether any *other* ledger
transition overwrites the same way - this was found by diffing one entry across
one reopen, and the fix should be chosen after looking at the writer, not
generalised from this row. **Look for an existing preserve path before adding
one** - the ledger already carries a `fixed`/`fixed_sha` pair it knows how to
write, so the machinery may be present and simply not reached on this edge.

## Gate

Track T's own quick tier, per the per-fix loop in CLAUDE.md - do not widen it.
Plus a guard that drives one signature through open, then fixed, then reopen over
a scratch ledger and asserts the original discovery survives. **That guard must
fail against today writer before it is believed** - a guard that passes on the
unfixed code is measuring nothing.

---

## 2026-08-29 — fixed, in two units. Your framing held; the writer says it is one
## edge wider than you measured, and one field worse.

### The preserve path did already exist — you called it

`recheck()` marks a finding fixed by **mutating** the entry in place
(`e["status"] = "fixed"`, `e["fixed"] = ...`). Only the reopen edge replaced
instead of mutating. So this is one path rejoining the other, not new machinery,
exactly as the ticket predicted. `ledger_record()` had:

```python
if e is None or e.get("status") == "fixed":
    led["findings"][sig] = { ...a whole fresh entry... }
```

The `or` is the entire bug: a reopen took the first-sighting branch.

### Your unmeasured check, now measured — I read every write into an entry

The ticket says *"whether any other ledger transition overwrites the same way …
the fix should be chosen after looking at the writer, not generalised from this
row."* Audited: `ledger_record`, `ledger_ticket`, `recheck`, and the publish path
are the only writers into `findings[sig]`. Every one of the others mutates named
keys. **The wholesale assignment above was the only overwriting transition** — so
the generalisation from one row was correct, and it is now correct by audit
rather than by shape.

### One field beyond your table, and it is the worse one when it bites

`ticket` was erased too. A signature someone had already filed a ticket for comes
back looking **untriaged**, and gets triaged again — while `ledger_ticket()` keeps
`ticket` and `status` paired and both count as open for throttling. So the status
must return as `"ticketed"`, not `"open"`, when the link survives; handing back a
ticket slug beside `status: "open"` would split a fact from its evidence in a
second field, which is the defect this ticket is about.

Not a correction to your framing — an addition to it. Your table is accurate on
every row I could check, including the two you inferred rather than measured.

### What landed

**Unit 1 — `a3387878e`, `tools/pasmith_run.py`.** `ledger_record()` mutates in
place on reopen: `first_seed`/`first_sha`/`opened` keep meaning *first*,
`examples` appends, `hits` increments, `ticket` survives with its paired status,
and the retired `fixed`/`fixed_sha` pair is moved into a `reopens: [{fixed,
fixed_sha, reopened, reopened_sha, reopened_seed}]` list — so the **bisect
bracket is explicit and survives repeated cycles** rather than being one pair the
next reopen overwrites.

**Unit 2 — `tools/twatch.py`.** The announce partitions `new` into `NEW:` and
`REOPENED:` by reading `reopened_from_fixed` back from the published ledger:

```
tstate(plexus): fuzz eb1b200ee92f — NEW: a; REOPENED: b (1 divergence(s) in 200 programs)
```

Read back from the ledger rather than threaded through the caller, because the
writer sets the flag at the moment it knows, and a signature only enters `new` by
being newly opened or newly reopened — so the flag partitions the list exactly.
An unreadable ledger degrades to `NEW`, never to silence: a mislabelled event is
better than an invisible one, and that is a guard, not a comment.

### Guards — 14 in `tools/pasmith_ledger_reopen_devtest.py`

Run against the **unfixed** writer first, per this ticket's own instruction:
**6 of 10 failed**, including the ticket-link guard, which is how the extra
finding above was confirmed rather than argued.

The four announce guards were mutation-tested three ways — pre-fix behaviour
(all `NEW`), inverted partition, and silence on an unreadable ledger. Each fired
on exactly the guards it should. The silence mutation surfaces as
`IndexError: list index out of range` rather than a wrong string, which is the
right shape: there was no message at all to assert against.

One fixture note worth keeping: `_fresh()` initially left `opened` at
`utcnow()`, so a reopen in the same second would have overwritten it invisibly
and the guard would have **passed on the broken writer**. Back-dated to the
measured 2026-07-14 instance. It did not bite, but only by luck of the clock —
the same aperture problem as the bug.

## Log
- 2026-08-29 — unit 1 (writer) `a3387878e`; unit 2 (announce) `658666ea8`.
- 2026-08-29 — resolved.
- 2026-08-29 — resolved, commit 552eb213d.
