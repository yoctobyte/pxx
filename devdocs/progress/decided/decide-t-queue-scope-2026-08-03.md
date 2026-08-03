---
summary: "User calls on four standing assumptions in the Track T queue: borg's watcher, the arm oracles, who may pin, and when the NilPy fuzzer earns its keep"
type: decide
track: T
prio: 60
status: decided
---

# Four Track T assumptions, settled

- **Type:** decide (Track T queue scope)
- **Decided:** 2026-08-03 by the user, asked during a T-queue triage. Several
  open tickets rest on assumptions that were true when filed and had drifted
  since; this records the answers so the next agent does not re-ask or, worse,
  build on the stale reading.

## DECIDED

### 1. borg's watcher — undecided/occasional, so handle it by TIME, not by a flag

borg is still the dev box (it holds the `gh` credentials and leads the dev
lanes — `two-box-protocol.md`); only its *watcher daemon* stopped, on
2026-07-31. It may run again now and then.

So a host is not "retired" — it is **quiet**, and quietness is a property of
the clock, not a state anyone declares. Readers suppress a host's open
regressions once its newest verdict is older than a threshold, and the
suppression **reverses by itself** the moment that host publishes again. No
`trackt retire`, no flag to forget to unset. Rules out option 2 of
[[task-t-borg-open-regression-is-permanently-stale]]; the suppression must be
VISIBLE (a host going quiet unnoticed is its own failure mode).

### 2. The arm32/arm64 rPi oracles — aspirational, no date

No arm hardware exists yet (nothing in `~/HardwareInventory/`). Tickets that
build machinery for a multi-host arm topology are design records, not ready
work: [[feature-t-host-roles-native-vs-qemu-topology]] moves to `rainy-day/`.

Where such a ticket has a half that pays off on **xeon alone**, that half stays
live and is built now — e.g. the "a sweep that reds >N% of the matrix is an
infra fault, not a regression" guard in
[[task-t-suppress-autoticket-until-host-baselined]], which is worth having on a
single host and would have caught xeon's own 17-job cascade.

### 3. Pinning — testmgr owns it, and the WATCHER may pin

[[feature-t-testmgr-owns-pinning-interruptible]] asked for this call
explicitly, because pinning writes to the repo and Face 1's rule is "the
watcher writes only `tstate/`". The answer is that the watcher **may** pin, as
a new and clearly-scoped capability.

That makes the scoping the load-bearing part, not an afterthought: the pin path
must be opt-in per host, must be visible in `trackt status`, and must be atomic
with respect to interruption — either the pin completed and the stable tree is
staged (`make pin` must `git add` it), or the tree is untouched. "Writes only
tstate/" becomes "writes only tstate/, plus the stable tree when pinning is
enabled on this host".

### 4. The NilPy differential fuzzer — wanted, but not while NilPy is this young

[[feature-t-nilpy-cpython-differential-fuzzer]] stays on the board and stays
wanted. It does not get worked yet: NilPy has a large known-bug backlog, and a
fuzzer against a surface with that many open defects produces findings that are
already-known noise, burying anything new. It earns its keep once NilPy is
stable enough that a fuzz finding is likely to be a NEW bug.

The user's reading of the existing fuzzers, which is why this is a scheduling
call rather than a rejection: **they have stopped reporting new issues, and
that is a good sign, not a dead end.** What has paid off instead is pulling in
**real-world libraries** as corpus — that is the direction to invest tooling
in. So: prefer corpus/real-code breadth over more synthetic generation while
the known-bug backlog is large.

The other three harnesses ([[feature-t-uforth-benchmark-harness]],
[[feature-t-windows-wine-harness]], [[feature-pasmith-qplus-rplus-rungs]]) stay
live and unchanged in priority.

## Log
- 2026-08-03 — recorded from the user's answers; the affected tickets were
  updated the same commit.
