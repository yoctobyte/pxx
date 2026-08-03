---
summary: "borg's watcher was stopped 2026-07-31 with one open regression recorded; nothing will ever clear it, so every --status and gate.sh check reads a dead host's red as live"
type: task
track: T
prio: 40
status: done
owner: claude@xeon
---

# A retired host's open regression never clears

- **Type:** task (Track T tooling / tstate hygiene)
- **Opened:** 2026-08-02 by `claude@xeon` while triaging the T queue.

## Symptom

Every reader of tstate — `twatch --status`, `gate.sh check`, `TSTATE.md` —
still prints:

```
tstate: host borg  last b5b50be85d2d GREEN (native, 2026-07-31T17:51:50Z); full through f3d420def527 RED
tstate:   open regression: fpc-bootstrap#src:compiler/compiler.pas bad=b1976742df2c (1 in range)
```

`borg`'s daemon was stopped on 2026-07-31 when xeon became sole watcher
coverage (`two-box-protocol.md`, "Write scopes"). A regression clears when a
later run on **that host** passes the job. borg will never run again as things
stand, so this line is immortal: three days old today, and it will be three
months old unchanged.

## Why it matters more than it looks

It is not cosmetic — it degrades the signal every agent is told to trust:

- an open regression is the thing agents are supposed to act on, and this one
  cannot be acted on at all
- it is *plausible*: `fpc-bootstrap` on `compiler/compiler.pas` reads like a
  live bootstrap break, so each new agent re-investigates it
- it trains readers to skim the "open regression" lines, which is exactly the
  habit that makes a real one get missed

## The fork (pick one — this is a small design call, not obvious)

1. **Stale-host suppression in the reader.** A host whose newest verdict is
   older than N days is reported as RETIRED and its open regressions are
   filed under it rather than mixed into the live list. No data lost, works
   for any future host that goes quiet (a Pi oracle powered down, a container
   that stops being enrolled). Most general; a little more code in every
   reader — route it through `states_at()` per
   [[task-t-worktree-is-not-current-state]] rather than each reader
   re-deriving it.
2. **Explicit retirement.** `trackt retire <host>` marks `borg.json`, readers
   skip retired hosts. Honest and cheap, but manual — nothing prompts anyone
   to run it, so the next quiet host repeats this exact ticket.
3. **Re-test it on xeon.** The regression is against `b1976742df2c` on a job
   that xeon also runs; a green there does not clear borg's entry (verdicts
   are per host, by design — the toolchain gap is the point), so this
   answers the *compiler* question without answering the *display* one.

Recommendation: **1**, with the caveat that "retired" must be visible rather
than silent — a host disappearing quietly is its own failure mode, and the
whole reason `--status` exists is to notice a watcher that stopped.

## Not in scope

Whether borg should watch again. That is the user's call about the fleet, not
a tooling decision — if borg re-enrols, it publishes under its own `borg.json`
and this entry resumes meaning something.

## Log
- 2026-08-03 (`claude@xeon`) — option **1** (stale-host suppression in the
  reader), per the user's call that borg's watcher is undecided/occasional
  ([[decide-t-queue-scope-2026-08-03]]). That answer is what rules option 2
  out: an explicit `trackt retire` would have to be undone by hand the next
  time borg runs, and nothing prompts anyone to do either.

  So quietness is read from the clock — `last.date` older than
  `QUIET_HOST_SECS` (2 days) — and it reverses itself the moment the host
  publishes again. `host_quiet_secs()` is one helper used by both readers, so
  `--status`, `trackt status` and `gate.sh check` (which shells out to
  `--status`) all agree rather than each re-deriving it, as
  [[task-t-worktree-is-not-current-state]] asks. It reads `last.date`, never a
  file mtime, for the same reason.

  Held, never hidden — the ticket's caveat is the load-bearing part. The host
  line gains `[QUIET 3d2h — not publishing]`, the entries are replaced by a
  named count rather than dropped, and TSTATE.md grows a "Held — quiet hosts"
  section that says why nothing can clear them. A host going quiet is now MORE
  visible than it was, which is what `--status` exists for.

  Verified against live tstate: borg shows QUIET 3d2h with its one entry held,
  xeon's live state is untouched, and `tstate: UP` still answers the question
  the command is read for. `tools/twatch_quiet_host_devtest.py` pins the
  threshold, the never-ran case (being enrolled is not being abandoned), the
  live-host-beside-a-quiet-one case, and the reversal.
- 2026-08-03 — resolved, commit PENDING-COMMIT.
