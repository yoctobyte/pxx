---
slug: bug-t-a-pin-verifys-reds-carry-no-reasons
title: A pin verify's reds carry no reasons, so the jobs most needing triage are the ones with nothing recorded
track: T
kind: bug
prio: 40
status: done
owner: pxx-a5
---

# A pin verify's reds carry no reasons

`pin_verify.red` is a list of job NAMES. The reasons live in `job_reason`, which
is the *current* red set from the newest run — set-or-clear, which is correct
behaviour and is why it cannot answer this question.

The two diverge exactly when it matters. Measured 2026-08-19: the v367 verify at
`d47acfee770c` listed 20 reds; `job_reason` held 9 entries, and they were the 9
*inherited* reds that were still failing at HEAD. The 11 the reader actually had
to triage — the new ones, the ones a `make revert` trigger fires on — were
precisely the 11 with no reason recorded anywhere, because they were green by
the time the newest run wrote the map.

A peer hit this the same night and spent six commands reconstructing by hand what
a stored reason would have answered in one look.

## Why the obvious fix is not obviously right

Storing reasons under `pin_verify` costs tstate size on every verify, and tstate
is published to git on every cycle — this is the file every track fetches. The
9-entry map is already the largest variable-size thing in it. So the ticket is
not "add a field"; it is:

- **Which reasons?** Only the reds NOT in `pin_baseline.reds` — the new ones —
  would have covered the whole incident at ~11 entries instead of 20.
- **Truncated how?** `job_reason`'s entries are already the compact form. A
  first line, or a byte cap per entry, keeps the growth bounded.
- **Or not stored at all?** The report JSON for the verify run exists on the
  watcher box and has every reason in it. A pointer (run id + host) that
  `--follow`/`--why` can fetch on demand is cheaper in the shared file and
  strictly more informative — at the cost of only working while that box is up
  and the log is unreaped. `report_job()` already drops `log` for exactly this
  reason: the path does not survive the box.

That last fork is a genuine design call, not a detail, and it decides the shape
of the change.

## Interaction with the corroboration line (57d5880ce)

Now that `--status` refutes a load-shaped count against a later full tier, the
reasons matter LESS for the noise case and MORE for the real one: once the line
says "corroborated in part: 3 of 11 also fail", those 3 are a genuine regression
at the pinned tree and the reason is the next thing anyone asks for. Do this
after living with the corroboration line for a bit — it changes which reasons
are worth the bytes.

## Acceptance

A reader seeing `N new` reds in `--status` can get the reason for each without
leaving the tool, and `tstate/plexus.json` has not grown by more than a bounded
amount per verify (state the bound and measure it against a real verify).

Filed by plexus-T 2026-08-20 from a peer report. Not urgent — the peer explicitly
did not ask for it that night; it is recorded where it bit.

---

## 2026-08-29 — fixed. The fork is settled by a fact that post-dates the ticket.

### The fork: STORED, not pointed at

The ticket left this open and called it *"a genuine design call, not a detail"*.
It is, and two things settle it for storing:

- **A pointer resolves only while that box is up and its log unreaped**, and the
  moment anyone needs a pin verify's reason is a moment when things are already
  broken. `report_job()` already drops `log` for exactly this reason — a path
  does not survive the box, and this is the same lesson one level up.
- **A second box is arriving.** tstate is the shared file every host and every
  track fetches; a pointer keyed to `host + run id` is unresolvable *from the
  other box by construction*, so the pointer design gets worse precisely as the
  fleet grows. That fact post-dates the ticket (filed 2026-08-20) and is what
  turns a close call into a clear one.

The ticket also said to do this *"after living with the corroboration line for a
bit"*. Nine days, and the interaction it predicted holds: the reasons are
printed **after** the corroboration line, because that line is what tells a
reader which reds are real, and a reason offered before it invites triage of a
flake.

### The bound, stated and measured as the acceptance asked

Three bounds, because this file is fetched by every track:

| bound | value | why |
| --- | --- | --- |
| new reds only | — | a red already in `pin_baseline.reds` was failing before this pin and is not the triage subject |
| per-entry cap | 200 chars | so one pathological log cannot crowd out nineteen useful ones — the failure mode of a single shared byte budget |
| entry-count cap | 20, and it SAYS what it dropped | a cap that trims silently turns "we kept 20 of 40" into "there were 20" |

**Measured worst case: 4,230 bytes** (20 entries, every one at the cap) against
a 737 KB `plexus.json` — 0.57%. The realistic case is far smaller: reasons run
~147 characters at the median, and the worst *actual* incident (v367 at
`d47acfee770c`) had 11 new reds, so ~1.6 KB. The measurement is a guard, not a
comment, so raising a cap fails a test rather than quietly growing the file.

A job whose run recovered no log gets **no entry**, not an empty one. An empty
reason beside a job name reads as *"there was no reason"*, which is a claim;
absence reads as *"not recorded"*, which is the truth.

### What a reader sees

Absence is reported too, and says which kind it is — a verify predating the
field carries no reasons and never will, and `job_reason`'s entries belong to
the **newest run**, not to this verify, so the line explicitly says not to read
them as these. That line fires only when there *are* new reds; with zero new
reds there is nothing to explain and it would be noise.

### Guards, and the one arm they do not cover

9 in `tools/twatch_pin_verify_why_devtest.py`, over the extracted pure
`pin_verify_why()`. Four mutations, each confirmed to have applied before its
result was read: inherited reds stored too (3 fired), no per-entry truncation (2),
no entry-count cap (1), empty reasons stored (1).

**Known aperture, stated rather than glossed:** the guards cover the WRITER. Of
the reader, only the *absence* arm was exercised live; the has-reasons arm was
not. `status()` takes its state from `states_at(repo, ref)` — the **committed**
tstate of twatch's own repo — so exercising that arm needs a committed tstate
carrying a new red, which a scratch tree and a `--clone` both fail to supply.
Three attempts are recorded here rather than a fourth being made: a working-tree
injection is invisible (states_at reads the ref), `--clone` needs a real repo,
and a scratch repo is ignored because `repo` comes from the script's location.

That arm will first run at the next pin verify that has a new red. It is
straightforward rendering of a dict the writer is proven to produce, so the
exposure is a wrong format string rather than a wrong verdict — but it is
untested, and saying so is cheaper than someone later assuming otherwise.

## Log
- 2026-08-29 — resolved.
- 2026-08-29 — resolved, commit 4508af516.
