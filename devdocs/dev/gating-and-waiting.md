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
The one-liner: `gate.sh quick` per fix, then push; breadth is Track T's, run
against your exact SHA. `full` is for when T is *proven* down.

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

### `pgrep` matches your own watcher

```bash
until ! pgrep -f "make test" >/dev/null; do sleep 30; done   # NEVER EXITS
```

The watcher's own command line contains `make test`, so `pgrep -f` finds itself
and the loop runs forever. This actually happened, twice, and looked exactly like
a stuck build. Wait on a marker file or on the job's own exit, not on a pattern
that your waiting command also matches.

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
