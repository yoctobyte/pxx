# Gating, and how to wait for a long run

Written after a session lost hours to its own waiting pattern rather than to any
compiler problem. Both halves below are cheap to get right and expensive to get
wrong, and neither is obvious from the Makefile.

## Run the gate as ONE command: `tools/gate.sh`

```
tools/gate.sh quick     # make test-nilpy + self-host fixedpoint + testmgr --tier quick
tools/gate.sh lib       # make lib-test              (Track B / E)
tools/gate.sh full      # quick + make test          (only when Track T is down)
tools/gate.sh check     # what it would run, plus the box's state and twatch status
```

It prints one line per step with its duration, `GREEN`/`RED` at the end, and exits
with the gate's status. Logs land in one directory, named per step, and a failing
step tails its own log — so a red does not start with a hunt for the log file.

**Background THIS, not the individual makes.** An agent that starts
`make test-nilpy` in the background and then polls it with `sleep 600; tail log`
spends a conversation turn per poll and learns nothing in between; the loop is
what makes a 20-minute gate feel like a hang. `tools/gate.sh` exits when the gate
is done, so the completion notification IS the result: one task, one answer.

If you must wait on something else, wait on a CONDITION that ends
(`until [ -f done.marker ]; do sleep 10; done`), never a fixed sleep you re-issue.

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
