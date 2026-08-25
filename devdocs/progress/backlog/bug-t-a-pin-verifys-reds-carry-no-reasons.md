---
slug: bug-t-a-pin-verifys-reds-carry-no-reasons
title: A pin verify's reds carry no reasons, so the jobs most needing triage are the ones with nothing recorded
track: T
kind: bug
prio: 40
status: backlog
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
