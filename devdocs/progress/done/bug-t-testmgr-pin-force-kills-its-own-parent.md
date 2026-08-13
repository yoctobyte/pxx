---
track: T
prio: 80
type: bug
blocked-by: []
summary: "`tools/testmgr.py --pin` SIGKILLs itself and pins nothing (exit 137). It holds the repo lock for the whole pin, then spawns the gate as a child with --force — and the child's acquire_lock(force=True) kills the pid it finds in the lock, which is its own PARENT. Broken by construction: --pin cannot succeed. A second path (the heartbeat reaper) kills the same parent independently."
status: done
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

## Resolution — 2026-08-13 (Track T)

Option 1, as filed: **ownership is passed down instead of re-acquired.** Both
kill paths are closed, because closing either one alone leaves `--pin` broken.

1. **`TESTMGR_LOCK_INHERITED=<pid>`** — `run_pin` spawns the gate child with the
   pin's own pid in the environment, and **without `--force`**. `acquire_lock`
   checks that variable first: if the lock file names that pid and that pid is
   alive, it returns True having touched nothing. The child therefore does not
   acquire, does not kill, does not release (`release_lock` already no-ops on a
   pid that is not ours) and does not heartbeat (`start_heartbeat`'s loop
   returns for the same reason). The parent does all three for the whole window,
   which is what the lock comment always intended.
   Survives `reexec_scoped()` because that re-exec inherits `os.environ` — the
   same property `TESTMGR_SCOPED` already depends on to avoid re-scoping forever.
   If the promised lock is *gone* (force-taken by a third run, or its holder
   died) the child **refuses** rather than taking one of its own: the window it
   was supposed to run inside no longer exists, and the alternative is to start
   killing on behalf of a parent that may itself be dead.

2. **The pin now heartbeats.** `start_heartbeat("pin")` runs in the `--pin`
   branch beside `acquire_lock`, so the lock stays `live` for the gate +
   stabilize-fast window. Without it any reader — its own child included — reaps
   the pin as wedged after 120s, and a pin whose gate is not already green
   exceeds that routinely.

3. **Backstop:** `kill_run` refuses `os.getpid()` and `os.getppid()`. Weak by
   itself (systemd adopts a scoped run, so `getppid()` becomes 1) — deliberately
   a backstop for whatever else learns to call it, not the fix.

`--force` keeps its original meaning at the top level (kill a live run and take
over) and no longer leaks into the child, where it never meant that.

### Verified

- `tools/devtest_pin_lock_inherit.py` — 5 cases, new: the child neither takes
  nor kills an inherited lock; it does not release its parent's lock on exit;
  a vanished inherited lock is refused, not seized; a pin lock beats often
  enough to read `live` (asserted through `lock_state`, the thing the reaper
  actually consults, not through the existence of a thread); and `kill_run`
  spares self and parent while still killing an unrelated run.
- `tools/devtest_pin_atomic.py` — 4 cases, unchanged and still green.
- **The end-to-end run this ticket says was missing.** `git clone --shared` to a
  scratch tree, seeded with a self-hosted binary, then a real
  `tools/testmgr.py --pin`:

  ```
  testmgr --pin: gate — tier quick at 4a4b18824a00 (~30s)
  testmgr: scoped — MemoryMax=37162M MemorySwapMax=1024M
  testmgr: using the repo lock held by pid 1590087 (inherited)
  ...
  testmgr: GREEN
  testmgr --pin: gate GREEN
  testmgr --pin: stabilize-fast (~40s — self → next → fixedpoint, byte-identical)
  testmgr --pin: applying the pin (uninterruptible from here — microseconds)
  testmgr --pin: pinned 8b66af75d4bc (7 builtin source(s) frozen), 6 file(s) STAGED
  EXIT=0
  ```

  Note the first attempt in that clone failed differently and usefully: a fresh
  clone has no self-hosted seed, so the gate reported INFRA and the pin stopped
  with the tree untouched — the correct behaviour, and a reminder that a scratch
  clone needs a seed copied in before it can gate anything.

### On the test gap

The ticket is right that a single scratch-clone `--pin` would have caught this
on the first try, and that is now the shape used above. The reason it was not
run when `--pin` landed is worth recording plainly: the devtests exercised
`apply_pin_atomic` — the part with the interesting invariants — and the lock
handshake was assumed rather than measured, on a path that fails 100% of the
time. The unit tests were the sophisticated ones; the missing test was the
stupid one.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
