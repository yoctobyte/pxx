---
track: T
prio: 80
type: bug
blocked-by: []
summary: "`tools/testmgr.py --pin` SIGKILLs itself and pins nothing (exit 137). It holds the repo lock for the whole pin, then spawns the gate as a child with --force — and the child's acquire_lock(force=True) kills the pid it finds in the lock, which is its own PARENT. Broken by construction: --pin cannot succeed. A second path (the heartbeat reaper) kills the same parent independently."
---

# testmgr --pin force-kills its own parent, so it can never pin

- **Type:** bug (the command cannot succeed) — **Track T** (owns
  `tools/testmgr.py`). Filed by an A+C+P+N agent that hit it while pinning a
  builtin change; **T owns the tool, so this is filed, not fixed.**
- **Found:** 2026-08-13, first use of `--pin` after it landed
  (`bec9b447f` feat(T): testmgr --pin, `c894096dc` fix(T): --pin gates QUICK).

```
$ tools/testmgr.py --pin
testmgr --pin: gate — tier quick at db8a1a4fc7d3 (~30s)
testmgr: scoped — MemoryMax=9570M MemorySwapMax=1024M
testmgr: --force — killing the live run (pid 1254225) and taking over
testmgr: killed run pid 1254225 — superseded by --force
testmgr: killed run pid 1254225 — wedged (no heartbeat for >120s)
Killed
$ echo $?
137
```

`1254225` is the `--pin` process itself. Nothing is pinned; the tree is left
untouched (which is the one mercy — `pinned` stayed at v267 and no half-pin
resulted).

## Mechanism

1. `main()`'s `--pin` branch calls `acquire_lock(args.force)` and writes the
   lock with `"pid": os.getpid()` — deliberately, and the comment says why:
   *"The repo lock is held for the WHOLE pin, gate included: a concurrent tier
   run would rebuild compiler/pascal26 under stabilize-fast's feet."* Correct
   intent.
2. `run_pin()` then runs the gate as a CHILD: `subprocess.run([... "--tier",
   tier, "--force"])`, commented *"--force because THIS process holds the repo
   lock for the whole pin, which is the point"*.
3. The child reaches `acquire_lock(force=True)`, sees `state == "live"`, and
   does `kill_run(info["pid"], "superseded by --force")` — where `info["pid"]`
   is **the parent**.

So `--force` was intended to mean "the lock you'll find is mine, proceed
anyway" and is implemented as "kill whoever holds it". The parent is the
whoever.

**Second, independent kill path:** the `--pin` branch never calls
`start_heartbeat()` (that lives in the tier path, after `acquire_lock`), so the
pin's lock has a `heartbeat` that never advances. After `HEARTBEAT_STALE`
seconds any reader — including its own child — reaps it as wedged. That is the
third log line. Fixing only the `--force` path would leave a pin longer than
120s still killable by its own child.

## Suggested shape (T's call)

The child does not need the lock at all — the parent already holds it for
exactly this window. Options, cheapest first:

1. Pass the lock ownership down: an env var (`TESTMGR_LOCK_INHERITED=<pid>`)
   or a `--inherit-lock` flag that makes `acquire_lock` a no-op when the
   holder is the caller's own ancestor. Also silences the heartbeat reaper for
   that pid.
2. Make `--force` refuse to kill `os.getppid()` (narrow, but leaves the
   heartbeat path).
3. Have `run_pin` release the lock around the gate child and re-acquire after
   — simplest, but reopens exactly the race the lock comment says it closed.

Whatever the shape, the heartbeat has to be handled too: either start one for
the pin, or mark the lock as "held by a pin, do not reap".

## Test gap this exposes

`--pin` shipped without an end-to-end run in a scratch repo. The Track T rule
is "test the tooling itself with QUICK tiers + a scratch bare repo" — a single
`--pin` against a scratch clone would have caught this on the first try, since
it fails 100% of the time, not intermittently.

## Workaround, for anyone blocked now

`make stabilize-fast && make pin`, then commit `stable_linux_amd64/**` — the
documented four-step manual route. Non-atomic (interrupting it can leave a
half-moved pin), which is the convenience `--pin` was built to provide.

## Gate

`tools/testmgr.py --tier full` green for T tooling changes, plus an actual
`--pin` run against a scratch clone.
