# `rainy-day/` — parked: real but not the current focus

Tickets here are **not active backlog** and **not yet shipped** — but parked does
**not** mean "unimportant or uninteresting." It mostly means **big work and/or
not directly language-relevant**, deliberately set aside so the active
`backlog/` reflects near-term language/compiler work. What lives here:

- **Big / not directly language-relevant:** extra CPU targets, OS ports,
  runtime/allocator infra, DWARF debug info, coroutine-runtime ports, backend
  auto-selection, bounded/arena memory profiles.
- **Ideas / stretch goals / policy:** speculative demos, a `uses X as Y` import,
  visibility enforcement, "compile the FPC compiler", the FPC-vs-PXX boundary
  doc.
- **Design parks:** standing decisions intentionally left open (no action until a
  call is made).

The line vs `backlog/`: a **language-relevant** feature (a directive, a
type-system or codegen capability) stays in `backlog/` even when low priority.
The line vs `done-followup/`: that bucket is for features that are **shipped and
usable** with only optional polish left; rainy-day items are not built yet.

Moving here is **reversible** — pull back to `backlog/` when it becomes active.
`tools/progress.sh` knows this status (own board column, README excluded from
counts); it does **not** satisfy `Blocked-by:` (nothing here is done).

## The float-accuracy quarantine (owner, 2026-08-19)

**Float accuracy is parked here by default.** Owner, verbatim: *"compiler syntax, segfaults,
etc, all prio. floating point, especially when 'mostly ok' (apart performance or insignificant
digits), very low prio. by definition"* — and *"it are cherries on the cake."* Stated three
times (08-15, 08-16, 08-19), so it is recorded where the scheduler looks instead of in prose.

**Why here rather than a new folder:** `rainy-day/` is already invisible to
`tools/progress.sh ready` and `next` (which scan only `urgent`/`working`/`unfinished`/
`backlog` — `tools/progress.py:647`). The quarantine the owner asked for already existed and
already held float tickets; it did not need inventing.

**What is parked:** ulps, last-digit rounding, formatting policy, subnormals, edge-of-range,
correctly-rounded-vs-fast tiers, and *performance* work whose subject is float. 14 tickets
moved on 2026-08-19.

### The escape rule — read this before parking anything else here

**Rank the mechanism, never the datatype.** These are NOT float-accuracy tickets and must stay
in the active backlog however many `Double`s they contain:

- a wrong value at scale or a saturation (`writeln fixed saturates at Int64`)
- a crash, a segfault, a hang
- a wrong signature or a control-flow bug that merely lives in float code
- a **missing** function a working CPython/FPC program calls (that is a frontend/RTL gap)

Left in `backlog/` deliberately for exactly that reason: `feature-a-extended-is-an-alias-for-double`
(type mapping), `feature-opt-inline-float-and-record-returning-leaves` (an inliner pass that
also covers records), `feature-nilpy-math-module-twelve-absent-names-measured` (absent names,
not inaccurate ones).

**Flagged as the closest call:** `bug-a-riscv32-softfloat-has-no-subnormals` is parked, but
absent subnormals is a *range* failure rather than a last-digit one. Un-park it if anything
real meets it.

### Parking does not close the door the tickets actually come through

De-ranking cannot stop the flow on its own, because **a red job is worked at the priority of
being red, not of its subject** — NilPy's `.expected` files are generated from CPython, so an
ulp move is a CI red at any prio. `meta-float-accuracy-policy` (Track U, p60) stays in the
active backlog for that reason: it is the decision that stops an ulp being able to turn a job
red, and it is the only float item that should be visible to `ready`.
