---
slug: bug-t-sync-sh-pulls-under-a-running-sweep-and-a-ticket-push-is-the-case-people-walk-into
track: T
prio: 45
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "`tools/sync.sh` does `pull --rebase` unconditionally, so running it during a sweep in the SAME checkout swaps test sources under a harness that reads them from the tree. Twice on 2026-09-06 by two seats who could both quote the rule: frankD lost a 2276-file census (two syncs, 4 files changed mid-sweep) and frankB lost a full suite over three Group 19 fixes (three ticket syncs; the tree picked up another seat's new test row against a binary built before it, and the RED landed on a file frankB had just edited so it read as theirs and had a plausible mechanism). THE HOLE IS EXACTLY THE SIZE OF THE WORK THAT FEELS SAFE -- nobody lands a code fix mid-sweep, and pushing a TICKET feels like paperwork; sync.sh does not know the difference because the pull is the same pull. A GUARD WAS WRITTEN AND NOT SHIPPED: argv-anchored, cwd-scoped to this checkout, refusing with a PXX_SYNC_DURING_SWEEP=1 escape. Its POSITIVE control fired correctly and its NEGATIVE control ALSO fired, so it was reverted rather than tuned -- sync.sh is in every lane's inner loop and a false refusal there is worse than the defect. THE DETECTOR IS NOW SOLVED (frankB): read a field the waiter cannot write into. argv is writable by every waiter and comm is not, so `pgrep -x make` matches the executable NAME and a shell running it cannot match its own probe -- a negative control that holds structurally rather than by luck. The bracket trick does NOT work (`pgrep -f '[m]ake test'` returns the identical pid set) because pgrep never puts its pattern in the matched processes' argv; that trick defends the tool against itself and does nothing about third parties. Measured: 3 orphan waiter shells match `pgrep -f`, aged 28.7h / 853s / 0s, the last being the measuring shell itself. Remaining work is the guard around that detector plus its devtest."
---

# sync.sh pulls under a running sweep, and the commit that does it is a ticket

**The rule already exists** — CLAUDE.md, *"PUSH BEFORE A MEASUREMENT STARTS, NEVER
DURING ONE"*, added the same day. **It was walked into twice anyway, by two seats
who could both quote it**, which makes this a placement and enforcement problem
rather than a knowledge one.

**Why prose is losing here, in frankB's words:** *"I did not think of a ticket
commit as touching the instrument. Landing a fix during a sweep is obviously
wrong and I would not have done it; pushing a `.md` felt like paperwork.
`sync.sh` does not know the difference — the pull is the same pull."* The rule as
carried is about CONTENT (do not edit code) and the correct form is about the
COMMAND: **any `sync.sh`, any `pull`, for any reason, is touching the
instrument.** And the rule is filed under *"push often"* — under the act, where
nobody about to start a measurement is reading.

**The tell exists and is nearly always missed.** frankB's run gave **rc 2**, which
the handbook records as the shape no test in the harness can produce. They read
the failing ROW instead of the exit code, and the failing row had a story: their
own edit, in the right file, with a plausible mechanism. *A red with a good
explanation is the one to check hardest.*

## The guard that was written, and why it is not in the tree

Insert before the fetch in `tools/sync.sh`; refuse with a documented escape
(`PXX_SYNC_DURING_SWEEP=1`), the pattern `no-full-suite.sh` already uses.

```sh
sweep_running_here() {
    for _d in /proc/[0-9]*; do
        _p=${_d#/proc/}
        [ "$_p" = "$$" ] && continue
        [ "$(readlink "$_d/cwd" 2>/dev/null)" = "$ROOT" ] || continue
        _a=$(tr '\0' ' ' < "$_d/cmdline" 2>/dev/null) || continue
        case "$_a" in
            "bash tools/gate.sh"*|"sh tools/gate.sh"*|tools/gate.sh*) echo "$_p $_a"; return 0 ;;
            *testmgr*--tier*) echo "$_p $_a"; return 0 ;;
        esac
    done
    return 1
}
```

Both halves of the predicate are deliberate and both are the day's lessons:

- **ARGV-ANCHORED at position zero, never a pattern match.** `pgrep -f` matches
  the asker's own command line and `grep -v grep` is blind to any process whose
  job is to grep — both cost sessions hours on 2026-09-06.
- **CWD-SCOPED to this checkout.** Every seat has its own tree, so a peer's sweep
  is none of our business — our pull cannot move their files. A guard firing on a
  peer's sweep would refuse constantly and be disabled inside a week.

**IT IS NOT SHIPPED BECAUSE ITS NEGATIVE CONTROL FIRED.** With no sweep running,
the detector still returned a hit — it matched the *testing shell's own command
line*, which contained the case patterns as literal text. **A guard against
instrument self-matching, whose own test self-matched.** The positive control (a
process with `argv[0]` = `bash tools/gate.sh quick` and `cwd` = `$ROOT`) fired
correctly, so the detector can fire; what is unproven is that it stays silent
when it should.

**Shipping it would have put a false refusal in every seat's inner loop** — far
worse than the defect, and `sync.sh` is the one script every lane runs. Reverted
rather than tuned, because a guard nobody trusts gets an env var permanently
exported and then it is not a guard.

**Whoever takes this: the deliverable is a NEGATIVE control that passes.** The
guard is easy; the control is the work.

## THE DETECTOR IS SOLVED, AND THE PROPERTY IS NOT THE ONE I WAS AIMING AT (frankB, 2026-09-06)

**Read a field the waiter CANNOT WRITE INTO.** `argv` is writable by every waiter
— that is the whole disease — and **`comm` is not.**

```
pgrep -f 'make test'   ->  5 pids     (1 real make, 3 orphan waiters, 1 my own probing shell)
pgrep -x make          ->  1 pid      comm=make
```

`pgrep -x` matches the executable NAME, so **a shell running `pgrep -x make`
cannot match its own probe** — its command name is `bash` whatever its arguments
say. Verified here: the probing shell does not appear in its own result. That is a
negative control that holds **structurally rather than by luck**, which is exactly
what this ticket was blocked on.

**AND IT KILLS THE OBVIOUS FIX FIRST.** The bracket trick does nothing:

```
pgrep -f 'make test'    ->  143678 363689 1655102 1772877 1772931 1906270
pgrep -f '[m]ake test'  ->  143678 363689 1655102 1772877 1772931 1906270
```

Identical. `[m]ake` works against `ps | grep` because **grep's own argv carries
the pattern**; `pgrep` never puts its pattern into the matched processes' argv at
all. **The trick defends the tool against itself and does nothing about third
parties**, and third parties are the actual failure mode.

**THE ORPHANS ARE THE DURABLE HALF.** Measured on this box: three `bash` processes
matching `pgrep -f 'make test'`, each an `until ! pgrep -f "make test"` loop whose
own argv contains the string it waits to disappear — so each can never exit, and
**while it lives it makes every other `pgrep -f 'make test'` in that session
answer YES.** Ages when measured: **103275s (28.7 hours)** in one checkout, 853s in
another, and 0s in a third — that last one being **this ticket author's own
probing shell, matching itself while measuring the defect.**

**A guard that is merely wrong fails once. A self-perpetuating waiter makes every
future check in that session wrong, silently, and outlives the thing it was
watching by a day.** Nothing cleans them up.

**Two caveats so the guard is not aimed wrong:**

- `-x make` finds any `make`, not specifically `make test`. If the distinction is
  needed, take the pid set from `pgrep -x make` and read `/proc/<pid>/cmdline`
  **per pid** — that set is already free of self-matches, so filtering it is safe
  in a way that filtering `pgrep -f` output is not.
- It will not see a sweep driven by something that is not `make` — a bare
  `testmgr`, `gate.sh`. **Name that limitation in the guard rather than widening
  back to `-f`**, or the hole reopens.

**And the corollary for every waiter in the fleet, which is the wider fix:
wait on a PID, not on a string** — `while kill -0 $pid 2>/dev/null; do sleep 5;
done`. A pid cannot match itself.
