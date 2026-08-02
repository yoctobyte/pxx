---
summary: "twatch auto-files a prio-70 stub on NEW-RED and never closes it when the job goes green again — the watcher's own ledger closes the regression, the ticket sits at the top of the ready queue forever"
type: feature
track: T
prio: 65
---

# The watcher files regression stubs but never closes them

- **Type:** feature (Track T tooling — auto-ticket lifecycle)
- **Opened:** 2026-08-02 by `claude@xeon`, found while triaging the T queue.

## The evidence

`regression-test-nilpy-test-nilpy-bytes-decode` was auto-filed 2026-08-01T21:05Z
at `74a925112afc` with **prio 70**. The fix landed the same evening
(`4d61f857e`, "add the real bytes(TPyList) overload"), and the watcher *itself*
recorded it: `a8f17aa2f tstate(xeon): 4d61f857edeb GREEN (full)
FIXED:test-nilpy#src:test/test_nilpy_bytes_decode.npy`.

The ticket stayed in `backlog/` at prio 70 regardless — for a full day, at or
near the top of `progress.sh ready --track T`, inviting every agent that ran
`next` to pick up work that no longer existed.

## Why it is a real cost, not tidiness

- **It outranks live work.** Stubs are filed at prio 70 (advisory ones at 40),
  which is above almost everything in the T queue. A stale stub does not sit
  quietly at the bottom; it sits at the top.
- **It costs a re-verification each time.** Anyone picking it must rebuild,
  re-run the repro and diff against tstate to discover it is already green.
- **It erodes the auto-file mechanism.** Once agents learn stubs are often
  stale, they stop trusting the ones that are real — which is the whole value
  of face-1 auto-filing.
- The watcher already **knows**: `diff_jobs()` computes `fixed`, and the
  ledger drops the entry via `reg_open()` in the same publish.

## Asked for

Hook the close onto the ledger, not onto a second invented rule. In
`publish_report`, the entries filtered OUT of `st["open_regressions"]` are
exactly the regressions the vetted state machine considers closed (that filter
already survived two incidents: the 2026-07-20/21 cascade that closed off one
lucky run, fixed by judging against the MERGED map). For each such entry:

1. Find its stub by the same `reg_slug()` / cascade slug used to file it.
2. **Only touch it if it is still an untriaged stub in `backlog/`** — the
   filed-by-twatch marker is present and no agent has moved it to
   `working/`/`blocked/`/`unfinished/` or resolved it. A ticket someone has
   picked up is theirs; the daemon must never move it.
3. Move it to `done/` with a log line naming the sha where the job passed, the
   tier that judged it, and the sha it was red at — so `progress.sh check`'s
   commit rule is satisfied and the close is auditable.
4. Publish as its own `tstate-ticket(<host>): closed …` commit, matching the
   existing file path's shape, and gate it behind the same `autoticket` config
   flag that files them.

## Deliberately not

- **No board regeneration from the daemon.** `BOARD.md` is generated and is the
  one file two agents always conflict on (`sync.sh` exists for it); the filing
  path does not regenerate it either. Keep parity — an agent regenerates.
- **No triage, no root cause.** Face 1 stays dumb: it opened the stub, it can
  close the stub. Anything else is face 2's job.
- **No reopening.** If the job reds again, the normal NEW-RED path files a
  fresh stub, which is correct: a second red is a second finding with its own
  range.

## Gate

Scratch bare repo, no long runs: file a stub, flip the job to pass, confirm the
ticket moves to `done/` with a truthful log line and a publish commit. Then the
three negatives, which matter more than the positive: a stub that an agent has
**claimed into `working/` is untouched**; a stub whose body has been **rewritten
by a triager is untouched**; and a **cascade** entry closes only when every job
it swept up is green, never on one lucky run.

## Log
- 2026-08-02 — resolved, commit 12f1cd965.
