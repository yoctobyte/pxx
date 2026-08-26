---
track: T
prio: 55
type: bug
blocked-by: []
summary: "A sha whose only run TIMED OUT is recorded in st[\"last\"] and therefore counts as tested for staleness: --status stops asking for it and the fleet reads it as covered. The run published no verdict by design (bug-t-the-native-tier-times-out-and-publishes-a-contentless-red, fixed 2026-08-25) — but the staleness question is a separate mechanism that still answers yes."
---

# A timed-out sha still counts as tested

Split out of `bug-t-the-native-tier-times-out-and-publishes-a-contentless-red`
after fixing its two report-format defects on 2026-08-25. Named there as an
explicit non-fix, and filed here rather than folded in, because widening scope
at the end of a session is how the next incomplete fix gets written.

## The mechanism

`test_sha()` records `st["last"] = {sha, date, verdict, wall, tier}` for every
run that produced a report — correctly, because a timed-out run DID measure
things and its statuses are real. Staleness then reads `st["last"]` to answer
"has this tree been tested?", and gets yes.

That is the wrong direction of error. A TIMEOUT means the run was torn down with
jobs undecided; the sha has partial coverage at best. Everything downstream that
consumes staleness — `--status` UP/DOWN, `testable_behind`, the breadth-stale
line, and now `breadth_overdue()` — treats it as a tested sha and stops asking
for it. So the one shape of run that proves the least is the one that most
effectively silences the request for more.

The verdict itself is now honest (`verdict: TIMEOUT`, `timed_out: true`, a NOT
REACHED list, and `last_full` deliberately not recorded). This ticket is only
about the *staleness* consumers, which ask a different question and never look
at the verdict.

## What to change, and the trap in it

The obvious fix — do not record `st["last"]` for an incomplete run — is wrong,
and this is the part worth reading before starting. `st["last"]` is also the
**parent** for the next run's diff (`parent = (st["last"] or {}).get("sha")`)
and the baseline the job map is built against. Dropping it would make the next
run diff against an older sha, which re-attributes every red in between and is a
much larger error than the one being fixed.

So: keep recording it, and give the staleness consumers a field to ask about.
`st["last"]["timed_out"]`, set from the report, with each consumer deciding
what a partial run means for its own question — `--status` should keep asking
for the sha; `breadth_overdue()` already ignores `st["last"]` entirely and needs
no change. That is four or five call sites, not a redesign.

## How it would show up

Quietly. `--status` reports UP with a sha that has no complete run behind it,
which is the same shape as the 08-19 incident where every statement was true and
none of them answered the question a reader took from them. There is no red to
notice; the tell is a tested sha whose only run has `timed_out: true` in
`runs-<host>.ndjson`.
