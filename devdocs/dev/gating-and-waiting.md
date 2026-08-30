# Gating, and how to wait for a long run

Written after a session lost hours to its own waiting pattern rather than to any
compiler problem. Both halves below are cheap to get right and expensive to get
wrong, and neither is obvious from the Makefile.

## Run the gate as ONE command: `tools/gate.sh`

```
tools/gate.sh quick     # self-host fixedpoint + testmgr --tier quick        (~30s)
tools/gate.sh lib       # make lib-test                          (Track B / E)
tools/gate.sh full      # quick + make test-nilpy + make test  (only when T is down)
tools/gate.sh check     # what it would run, plus the box's state and twatch status
```

`quick` deliberately does **not** run `make test-nilpy` — it once did, and spent
625 of its 649 seconds in that one suite: a full gate wearing the fast gate's
name, in the very mode agents are told to run per fix. `testmgr --tier quick`
carries dense NilPy and C canaries, and the whole nilpy suite is enrolled in
Track T's limited/full tiers, so the coverage is not lost — it is offloaded.

**Which mode to run, and why you must not widen it, is CLAUDE.md's call** — see
"THE PER-FIX LOOP" there; it is the authority and this file does not restate it.
Two things that are safe to say without restating it: breadth belongs to Track T
and runs against your exact SHA, and `full` is for when T is *proven* down
(`twatch.py --status` exit 1, or `trackt.py health` reporting DOWN — slow or
stale is not proven).

> **Corrected 2026-08-30 (frankD).** This paragraph used to end *"The one-liner:
> `gate.sh quick` per fix, then push"*, which contradicted CLAUDE.md — where
> `gate.sh quick` is **optional** per fix (run it when you touched something you
> are nervous about) and **required before a pin**, the one place the proof is
> mandatory. The line predated the 2026-08-25 change that moved the proof off
> the critical path; it did not disappear, it moved.
>
> Note the shape, because it is the one to watch for in any doc that defers to
> another: **the sentence declaring "this file does not restate it" was
> immediately followed by a restatement.** A deferral is not a safeguard — it
> reads as one, which is why the stale summary underneath it went unread for
> weeks. The reliable version of this pattern points at the authority and then
> *stops*.

It prints one line per step with its duration, `GREEN`/`RED` at the end, and exits
with the gate's status. Logs land in one directory, named per step, and a failing
step tails its own log — so a red does not start with a hunt for the log file.

**Background THIS, not the individual makes.** An agent that starts
`make test-nilpy` in the background and then polls it with `sleep 600; tail log`
spends a conversation turn per poll and learns nothing in between; the loop is
what makes a 20-minute gate feel like a hang. `tools/gate.sh` exits when the gate
is done, so the completion notification IS the result: one task, one answer.

**And then leave it alone.** Backgrounding the gate and then checking its log
every thirty seconds costs a turn per check and tells you nothing you will act
on — the completion notification is the event. Hand-polling a running gate is
the same mistake as a sleep-loop wearing different clothes; it happened twice in
the session that produced this file.

What you CAN do while a gate runs: keep exploring with the compiler binary as it
stands (compiling `.npy` files, reading code, writing tests or tickets). What you
must NOT do is run `make` — the gate is rebuilding that same binary, and a second
build mid-suite gives both runs a torn tree. If a change needs a rebuild, wait
for the notification.

If you must wait on something else, wait on a CONDITION that ends
(`until [ -f done.marker ]; do sleep 10; done`), never a fixed sleep you re-issue.

Do not pipe it (`tools/gate.sh quick | tail`) when you care about the exit
status — the pipe reports `tail`'s. The summary is already short; read it whole,
or use `${PIPESTATUS[0]}`.

**This is not a `gate.sh` rule — it is a rule about every command whose exit
status you intend to believe**, `make lib-test` and `make demos` included. It bit
again on 2026-08-28 in exactly that shape: `make lib-test 2>&1 | tail -25` reported
success while make had aborted with `Error 1`, and the run had stopped before
reaching the test the session had just added, so the "pass" covered a suite that
never ran the thing being gated. Redirect to a file and read it
(`make lib-test > log 2>&1; echo $?`); the log is there either way. The general
form is worth keeping in mind whenever a check is piped: **a check is only safe if
it prints a sentinel that failure cannot reach — if green looks like the ABSENCE
of output, a pipe or a `tail` can manufacture it.** That is also why every
`lib-test` entry ends in a positive `... OK` line rather than simply not failing.

**And the third member of the family, which is the worst of the three: a pipe can
destroy the DIAGNOSTIC.** The gate's own assertion shape,

```make
test "$$($(TESTTMP)/some_test | tail -n 1)" = "SENTINEL OK"
```

discards the program's output entirely when it does not match — `test` compares
and says nothing. On a reproducible failure that costs nothing, because you rerun
it. **On an INTERMITTENT it costs everything**, since the one run whose stdout you
needed is the one that will not happen again: on 2026-08-28 `lib_dns_libc` went
red once, passed a full gate re-run and fifteen direct runs of the same binary,
and left no record of what its last line actually said
(`bug-b-lib-dns-libc-failed-once-in-the-gate-and-claims-a-hermeticity-it-lacks`).
A line that captured stdout on mismatch would have made that a diagnosis instead
of a ticket. The first two members swallow a *status* and invert a
*verification*; this one deletes the *evidence*, and precisely where evidence is
irreplaceable.

**Fourth member, and it strikes one stage earlier than the others: `sort -u`
under a UTF-8 locale silently MERGES distinct identifiers.** Glibc's `en_US.UTF-8`
collation ignores punctuation, so

```sh
printf '_longjmp\nlongjmp\n' | sort -u     # prints ONE line
printf '_longjmp\nlongjmp\n' | LC_ALL=C sort -u   # prints two
```

Both names are declared in `lib/crtl/include/setjmp.h`, and on 2026-08-28 a crtl
declaration census dropped `_longjmp` exactly this way — no error, no warning,
a shorter list. The first three members corrupt the VERDICT of a check; this one
corrupts its INPUT, so the check then runs perfectly on a set that quietly lost a
member and reports an honest all-clear about the wrong thing. **Put `LC_ALL=C` on
any `sort` whose elements are identifiers, paths, or shas**, and when a tool
enumerates something, give it a floor it must clear (`test "$n" -ge 300`) so a
collapsed search fails loudly instead of passing trivially. The same census,
written a second time in Python, dropped `atexit` instead — for an unrelated
reason — which is the argument for diffing two independent enumerations against
each other rather than trusting either.

### `pgrep` matches your own watcher

```bash
until ! pgrep -f "make test" >/dev/null; do sleep 30; done   # NEVER EXITS
```

The watcher's own command line contains `make test`, so `pgrep -f` finds itself
and the loop runs forever. This actually happened, twice, and looked exactly like
a stuck build. Wait on a marker file or on the job's own exit, not on a pattern
that your waiting command also matches.

**The trap survives changing the mechanism.** Moving from `pgrep -f` to a
hand-written `/proc` scanner does not help: any detector whose pattern appears in
the command that runs it will find itself, and the second implementation feels
like a fix precisely because it is a different mechanism answering the same wrong
way. Measured twice in five minutes on 2026-08-30, in two different lanes.

### ...and the log you are told to read instead can be EMPTY (2026-08-30)

The advice above -- *do not ask the process table, read the job's own output* --
is right, and it has a failure mode that lands exactly when you need it.

**Python block-buffers stdout when it is not a tty.** A long-running tool
launched in the background, its output redirected to a file, accumulates every
line in an 8 KB buffer and writes nothing until it exits. Measured: a
`--minutes 40` fuzz run had **zero lines in its log after an hour**, and would
have filled in completely the moment the answer stopped mattering.

So the one artifact capable of distinguishing *slow* from *stuck* is empty for
precisely as long as the question is live. **If you depend on the subject
emitting, the subject has to be able to emit** -- and buffering is invisible
interactively, which is the only place anyone would ever notice it missing.

- **Writing a long-running Python tool:** `sys.stdout.reconfigure(line_buffering=True)`
  before the run starts, and guard it with a test, because it has no local
  effect. `tools/pasmith_run.py:1056` does this;
  `tools/pasmith_recheck_units_devtest.py:486` is the guard.
- **Waiting on someone else's tool:** run it under `python3 -u` or with
  `PYTHONUNBUFFERED=1` when you control the invocation.
- **When you control neither:** ask the **workdir**, not the log -- generated
  artifact count and newest-mtime answer *slow vs stuck* without the subject
  having to say anything. "196 seeds, newest 1 second old" is a complete answer
  and needs no cooperation from the process being watched.

The general rule this is an instance of: **ask the subject to emit; do not ask
the system whether the subject succeeded** -- grep the file for conflict markers
rather than trusting a resolver's exit status, look for `converged after N
round(s)` and diff the sha256 rather than trusting `make` to exit 0, which a
copied-in seed turns into a silent no-op. Each of those has been wrong in this
repo inside seven days.

## Match the gate to the situation

`make test` takes roughly three times as long as it looks like it should, because
`test-core` re-runs the whole nilpy suite inside it. The project rule (CLAUDE.md,
"confirm native, offload the matrix") is the cheap one: confirm natively with
`quick`, push, and let Track T's watcher run the breadth against your exact SHA.
Check `tools/twatch.py --status` first — exit 0 means T is up and the offload is
real; exit 1 means it is down and the full gate is yours to run.

## Track T's watcher shares your box

When the watcher is running here, `testmgr` saturates the CPU and every compile in
your gate slows by 2-3x. `tools/gate.sh` says so at the top rather than leaving
you to wonder why a familiar suite is suddenly taking 45 minutes. It is not a
reason to stop — just a reason not to read slowness as breakage.

## Writing a test that testmgr can sandbox

`testmgr` isolates a job by rewriting `/tmp` paths in the job's commands to a
scratch directory — **including the expectation string**. So an expected output
that literally contains an absolute `/tmp` path can never match: the program
prints `/tmp`, the rewritten expectation says `/tmp/testmgr-scratch-NNN`.

This is invisible in `make test-nilpy` (which does not sandbox) and shows up only
as a `test-core` red from the watcher, one push later:

```python
print(tempfile.gettempdir())          # expectation contains /tmp -> RED under testmgr
print(tempfile.gettempdir() == "/tmp")  # assert the property instead
```

Same rule for any path-shaped output: assert the property, or print a suffix.

## A gating worktree must not live under `/tmp` — and expected output must not name one

**Two rules, one mechanism.** testmgr rewrites absolute `/tmp` paths in expected
output and in recipe lines. So:

1. **An expected output must never contain an absolute `/tmp` path.** The program
   prints `/tmp`, the rewritten expectation says `/tmp/testmgr-scratch-N`, and
   they cannot match. A property of the test.
2. **A gating worktree must not live under `/tmp`.** Most recipe lines address
   the tree relatively after a `cd <REPO>` prefix that `Job.script()` builds
   *outside* the rewrite loop — but **not all of them do**, and one that names the
   tree by absolute path gets that path grafted into the scratch dir:

   ```
   pascal26: error: cannot read input file:
     /tmp/testmgr-scratch-541517/claude-1000/…/sweep/test/quick_canary_argv0.pas
   ```

   **It does not corrupt a random job — it corrupts the path job.** In a
   3081-job sweep exactly one job failed this way, and it was
   `quick_canary_argv0.pas`: the job whose *subject* is absolute-path handling is
   the one that names the tree absolutely. That is a prediction, not a
   coincidence, and it is why a single unexplained red in a `/tmp` run is worth
   checking against this before anything else.

   `.claude/worktrees/` is the right place. `/dev/shm` also works — its paths do
   not match `TMP_RE` at all.

**The failure mode is asymmetric and that matters operationally: it can only
produce a false RED, never a false GREEN.** A rewritten path makes a file
unreadable; it cannot make a failing test pass. So a run from a `/tmp` worktree
has trustworthy greens, and only its reds need triage — filter them by the
signature `testmgr-scratch-N/<your worktree dirs>` and re-run exactly those in a
clean tree. That is usually cheaper than restarting.

**Provenance of these two rules, kept because the process is the lesson.**
Rule 2 was first written from an incident whose own cause was **never
established** — a gate went RED from a `/tmp` worktree, the worktree moved, the
RED went away, and the seed-mtime no-op (now in CLAUDE.md) was live in the same
tree at the same time and alone explains that RED. Two variables changed, one
story fit. It was then narrowed away on a search of 105 job logs that found
nothing — and the signature appeared at log **684**. A correct rule, held for a
wrong reason, nearly deleted on an incomplete search.

## Do not put a worktree under `/tmp` — testmgr rewrites the path (2026-08-29)

This page already warns that **an expected output must never contain an absolute
`/tmp` path**, because testmgr rewrites those. The same rewrite bites a worktree
that is merely *located* there, and the symptom does not look like a path problem:

```
cannot read input file: /tmp/testmgr-scratch-NNN/<the whole worktree path>/test/...
```

testmgr mangles its own scratch root together with the worktree path. **The error
names a missing test file, so it reads as a broken or incomplete checkout rather
than as "you are standing in the wrong directory"** — which is the expensive part,
since the natural next move is to re-clone or re-fetch and the second attempt fails
identically.

Put scratch worktrees under `$HOME` (e.g. `~/pxx-irfix`), not `/tmp`. Found by the
wasm32 lane while gating the managed-string arg-temp consolidation; it cost a full
diagnostic detour on a gate that was otherwise clean.

**Companion trap, same session, same family:** starting `gate.sh` with a stale
`compiler/pascal26` on disk after an A/B build makes the gate compare a
fixedpoint-from-`pinned` against a binary built from different sources, and it
correctly reports *"two distinct fixedpoints"*. **The gate is right and you are the
contamination it names.** It prints the tell itself — `compiler/pascal26 is OLDER
than the last commit touching compiler/` — so read that note before diagnosing a
miscompile. Rebuild (`make compiler/pascal26`, ~12s) and re-gate.
