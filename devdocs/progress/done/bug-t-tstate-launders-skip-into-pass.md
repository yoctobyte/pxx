---
summary: "tstate records a SKIPPED job as \"pass\", so a green published state cannot be distinguished from one that actually ran — cross-host coverage differences are invisible exactly when they matter"
type: bug
track: T
prio: 50
status: done
---

# `skip` is published as `pass`, so green does not mean "ran"

- **Type:** bug (Track T — `tools/twatch.py`, tstate schema)
- **Opened:** 2026-08-03 by `claude@xeon`, split out of
  [[bug-t-corpus-regex-invents-phantom-tree]] item 3. That ticket fixed the two
  self-contained halves (the phantom corpus name, and one absent corpus taking
  an unrelated regression test down with it) and deliberately left this one,
  because it changes the tstate schema and wants a migration rather than a
  drive-by.

## The defect

`tools/twatch.py:587`:

```py
now = {job_key(j): ("pass" if j["status"] == "skip" else j["status"]) ...}
```

A job skipped because its corpus tree is absent on this box is published as
`pass`. The run-time warning is loud — `!! CORPUS MISSING — 33 job(s) will
SKIP` — but the **published** state is silently green, and every consumer of
`tstate/*.json` (cross-host comparison, `--status`, the dashboard, the cutover
decision) reads it as covered.

The comment's reasoning is sound as far as it goes: mapping skip to pass closes
an open regression when a box legitimately cannot run a job. The defect is that
it does so by **destroying the distinction**, rather than by treating a
third state as non-gating.

## Why it matters

Green must mean "ran and passed". Concretely:

- On xeon, 33 of the full tier's jobs skip when the corpus trees are unfetched
  — including all 24 c-testsuite conformance jobs. The verdict is still GREEN.
- A per-host `skip` count is the only thing that makes host-to-host coverage
  differences visible **at cutover time**, which is precisely when the fleet
  decides to trust one box's green over another's.
- It was also how the phantom-corpus bug stayed invisible for so long: the
  affected job read `pass` on every host while having never executed anywhere.

## Shape of the fix

1. Publish `skip` as its own status in `tstate/<host>.json`.
2. Keep it non-gating: `new_red` / `still_red` must not fire on it, and a job
   that goes red → skip still closes the open regression (today's behaviour).
3. Migration: existing `borg.json` / `xeon.json` carry `pass` for jobs that
   were skips. Readers must tolerate a missing/unknown status, so the safe
   order is (a) teach every reader the third state, (b) start writing it.
4. Report the per-host skip count in the tstate summary and the dashboard, so
   the coverage gap is visible without diffing two json files.

## Gate

`tools/testmgr.py --tier quick` green, plus a devtest over `diff_jobs` covering:
skip is not new-red; red → skip closes the regression; skip → red opens one.

## Stale — the fix landed 2026-08-08 and the ticket was never moved

`25c539758 fix(T): publish 'skip' as its own status — green must mean "ran and
passed"` (tools/twatch.py, tools/twatch_web.py, tools/devtest_skip_semantics.py).
Checked against this ticket's own four-point shape at 2026-08-13:

1. **Published as itself** — `diff_jobs` keeps the literal status:
   `now = {job_key(j): j["status"] ...}`, with the laundering conditional gone.
2. **Non-gating** — `PASSLIKE = ("pass", "skip")` is now the single shared
   definition; `new_red` / `still_red` test membership in it, so a skip opens
   nothing, and red -> skip still closes an open regression.
3. **Migration in the safe order** — the code comment records it explicitly:
   readers (`reg_open`, `gone_keys`, the status and index summaries) were taught
   the third state *before* anything wrote it, so states carrying `pass` for
   former skips stay readable and merely under-report coverage until the host
   publishes again.
4. **Visible count** — `tstate: coverage — N job(s) SKIPPED on <host>` in the
   summary, silent when a host skips nothing, plus the dashboard half in
   `twatch_web.py`.

Gate as specified: `devtest_skip_semantics.py` covers skip-is-not-new-red,
red -> skip closes, skip -> red opens. Still green today (it also grew three
cases for [[bug-t-testmgr-pin-force-kills-its-own-parent]]'s sibling fix to
`reg_open`).

Closed as **done**. Worth noting the known residual the fix left standing, since
it is not recorded anywhere else: a CASCADE entry whose jobs only ever SKIP
still closes wrongly, because skip is pass-like for closing. Publishing skip as
its own status did not change that, and `reg_open`'s docstring says so.

## Log
- 2026-08-13 — resolved, commit ec711cdec.
