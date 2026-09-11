---
slug: bug-t-gate-sh-never-reaps-its-log-dir-and-an-exit-trap-would-break-the-tool
title: "gate.sh never reaps its per-run log directory, and the obvious fix (an exit trap) would break the tool"
track: T
prio: 45
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [gate, tmp, cleanup, disk]
blocked-by: []
summary: "tools/gate.sh:24 is `LOGDIR=\"${TMPDIR:-/tmp}/pxx-gate-$$\"` with mkdir and NO reaper and NO trap. Measured 2026-09-11: 78 directories, 5.3G, oldest 2026-09-10, still accruing -- the real consumer behind that day's /tmp pressure, which had been relayed to several sessions as a scratchpad problem. DO NOT FIX IT WITH `trap ... EXIT`: gate.sh writes its summary AND every per-step log into that directory on purpose (its own comment at :27) so a backgrounded run can be read from it, which is what CLAUDE.md tells every seat to do because the wrapper exit code lies. A trap reaps GREEN runs first, so it looks harmless until the first red nobody can diagnose. RETENTION IS UNCONSTRAINED BY CODE: no program anywhere reads a gate dir -- `pxx-gate` appears in exactly one .sh/.py/Makefile file, gate.sh itself, which only ever writes its own $$-named dir -- so a few hours covers it. Recommended: age-based reap at gate START (never at exit, so a run cannot delete its own output) plus `kill -0 \"${dir##*-}\"`, since the dir name IS the pid, so a long concurrent run cannot be reaped by a threshold someone later tunes down. Rejected keep-on-red: it must read the verdict living INSIDE the directory it is judging, and getting that test backwards deletes exactly the reds. AND REAPING DOES NOT FIX THE `ls -td /tmp/pxx-gate-* | head -1` HAZARD -- it makes it WORSE-behaved: a smaller population returns your own dir more often, so a method already filed as wrong (playbook:12418) gets certified more and corrected less."
---

# What is measured

```
$ sed -n 24p tools/gate.sh
LOGDIR="${TMPDIR:-/tmp}/pxx-gate-$$"
$ ls -d /tmp/pxx-gate-* | wc -l      -> 78
$ du -shc /tmp/pxx-gate-* | tail -1  -> 5.3G
$ oldest                             -> 2026-09-10
```

No `trap`, no reaper, one directory per gate run, and `gate.sh quick` is
advertised as OPTIONAL PER FIX — so the rate scales with how well seats follow
the advice to gate often.

# Why the obvious fix is wrong, and this is the whole point of the ticket

`trap 'rm -rf "$LOGDIR"' EXIT` is what CLAUDE.md's own cleanup guidance
suggests for exactly this shape ("if cleanup genuinely matters, it belongs in a
committed script with a `trap ... EXIT`"). **Here it would break the tool.**

- The summary is written INTO `$LOGDIR` deliberately — `tools/gate.sh:27`
  says so in its own comment, because "background the gate and grep the LOG for
  the verdict" is the instruction everywhere, the wrapper's exit code having
  lied three times in one day.
- Every `FAIL` row prints `log: $LOGDIR/<step>.log`. Reading
  `pinned-rtl-canary.log` is how tonight's red was diagnosed.
- **The failure direction is silent and delayed.** A trap reaps green runs
  first, where nobody wants the logs, so it looks correct for as long as it is
  not needed. The first time it matters is a RED whose per-step log is already
  gone — and that reader has no way to know the log ever existed.

# What it probably wants instead

An **age-based reap** (delete `pxx-gate-*` older than N hours at gate START,
not at exit) or **keep-on-red** (reap only when every row passed). Both are
design calls with trade-offs — how long is long enough to diagnose, and does a
green run's log ever get read — which is why this is filed rather than fixed.
`/etc/tmpfiles.d/tmp.conf` is at 6h, so plexus already reaps these eventually;
the accrual above says it is not keeping up, and seven's `/tmp` is a tmpfs
where the binding limit is INODES and not bytes.

The trap caveat is frankZ's, who reached for the trap first and caught it.


# What reaping does NOT fix, and quietly makes harder to notice

**frankZ, 2026-09-11, and it cuts against this ticket's own fix.** Reading
another session's gate dir is an established practice and an established
mistake: `L=$(ls -td /tmp/pxx-gate-* | head -1); cat "$L/summary.log"` is in
`debugging-playbook.md:12418` under *"The two wrong ways, both of which look
careful"*, measured 2026-09-05 with three gates running, where `ls -td` returned
a different session's directory.

**Reaping shrinks the population of stale dirs, so `ls -td | head -1` returns
the caller's own dir more often.** The known-broken method therefore becomes
more reliable, which means it gets CERTIFIED more often and corrected less —
the passing-arrangement failure the fixture clause in CLAUDE.md describes,
arriving through a cleanup change nobody would connect to it.

This is not an argument against reaping. It is a statement that must be in the
ticket so no later reader takes *"we reaped the dirs"* as having addressed the
`ls -td` hazard. It does not. The two are independent and the reap makes the
second one quieter.

# Why age-based-at-start rather than keep-on-red

**Keep-on-red has to read the verdict that lives inside the directory it is
judging, and be right about it.** Invert that test once and it deletes exactly
the reds — a reaper whose failure mode is losing the only evidence anyone
needed. Age-based never reads a verdict: it needs a clock, and it degrades to
"you waited too long" rather than to "the evidence is gone".

**At START, never at exit**, so a run can never delete its own output.

**Plus one syscall to remove the clock coupling** (frankZ): a purely
time-keyed reap can delete a CONCURRENTLY RUNNING gate's directory if the
threshold is ever tuned below a long run's duration — a full gate is not a
30-second quick one, and whoever tunes it later will not be thinking about that.
The directory name IS the pid, so `kill -0 "${dir##*-}"` skips any live producer
and removes the coupling rather than relying on the threshold staying generous.

# Checking this ticket's own claims

`grep -n 'trap' tools/gate.sh` **returns a hit** — line 89, matching `bootstrap`
inside a comment. So the fast check of "is there a trap" answers YES and the
truth is NO. The word-boundary form is honest:
`grep -nE '(^|[^a-z])trap[[:space:]]' tools/gate.sh` returns nothing.
