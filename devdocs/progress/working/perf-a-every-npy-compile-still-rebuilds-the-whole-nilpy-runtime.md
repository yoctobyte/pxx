---
track: A
prio: 85
type: perf
blocked-by: []
summary: "The structural half of bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost, which halved the constant (8.62s -> 4.06s) by removing the hotspots but did NOT remove the WORK: every .npy compile still parses and code-generates all 24,460 lines of pylib.pas + pyeval.pas before it looks at the user's program. A zero-byte .npy costs 4.06s where `begin end.` costs 0.24s."
status: working
owner: agent-A-npytax
---

# Every `.npy` compile still rebuilds the whole NilPy runtime from source

Successor to **`bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost`**
(resolved 2026-08-26). That ticket found four hotspots inside the shared
codegen and removed them — the constant went **8.62s -> 4.06s, byte-identical
output, no coverage given up**. Read its RESOLVED section before starting here;
in particular its list of things that are already ruled out, so they are not
re-hunted.

What it did **not** do is remove the work. The injection is still unguarded:

```
compiler/pyparser.inc:34707    ParseUsesUnitAmbient('pylib');
compiler/pyparser.inc:34708    ParseUsesUnitAmbient('pyeval');
```

so `pylib.pas` (18,768 lines) and `pyeval.pas` (5,692 lines) are parsed and
code-generated on **every** invocation, before the user's source is looked at.
A **zero-byte** `.npy` costs 4.06s; `begin end.` in Pascal costs 0.24s.

## What is and is not still true

Still true, from the original diagnosis:

- flat in program size (an empty `.npy` and a real test land within noise);
- compute, not I/O;
- **DCE is not the lever** — it refuses on NilPy outright, and where it does run
  it cuts 34% of emitted code for ZERO wall-clock saving, because `dce.inc` is a
  post-pass and the compiler emits each routine as it parses it.

No longer true, and the reason this ticket exists at a lower prio than its
parent:

- "the compiler compiles the NilPy runtime at the same throughput it compiles
  itself, ~4 s/MB" — it is now ~1.8 s/MB, and the four fixes moved every
  frontend with it.

## The three options, re-costed

**Fix A — serialise/cache the compiled runtime unit image.** Still the only
route to ~0.3s. Still the same risk profile: the compiler has no unit-image
serialisation, emission is fused with parsing into one global `Code[]` plus
global `Procs`/fixup/RTTI/`UCls` tables, and the sharp edge is cache
invalidation — miss a key (a define, the target, an `-O` level) and the compiler
silently emits stale code. A conservative first cut keys on the full flag set
and refuses the cache on any unrecognised flag.

**Fix B — do not pull `pyeval` unless the program can reach it.** The cheapest
real slice, and the one to try first. The precedent is next door: `math` is
pulled only when the token scan sees `**`. `pyeval` is 5,692 of the 24,460
runtime lines. **Owned by Track N** — the two call sites are `pyparser.inc`'s —
so file/hand off rather than editing it under A. The hazard is documented in
`pyparser.inc` itself: *"the LAST unit named wins a name"*, so changing pull
order silently changes which `abs`/`min`/`max` a program resolves to. Verify
byte-identically against a program that does use `eval`.

**Fix C — lazy emission.** Rejected in `dce.inc`'s header ("means replaying
parser state per routine, per frontend") and bounded by the dead fraction, ~34%.

**Recommendation: B as the shippable increment (measure it first — if `pyeval`
is reachable from `pylib` the win is zero), A as the real fix, C is a trap.**

## Repro

```
: > /tmp/empty.npy
printf 'begin end.\n' > /tmp/tiny.pas
time ./compiler/pascal26 /tmp/empty.npy /tmp/o     # ~4.1s, 1780 procs, 2,231,705B code
time ./compiler/pascal26 /tmp/tiny.pas  /tmp/o     # ~0.24s
```

Gate when fixed: `make compiler/pascal26` (byte-identical fixedpoint) + the two
timings above re-measured in the resolve note, plus a byte-identical check of a
program that DOES use whatever was made conditional.

## Track T: what this costs the MATRIX (measured 2026-08-26, pxx-aa)

Filed here rather than as a new ticket — T owns the tool, never the bug. The
numbers are the tooling side of the same defect, and they are the reason this
ticket's `prio: 45` understates it.

### The tax is the whole job, not part of it

Measured at HEAD, i.e. **after** the hotspot fixes, on this box:

| compile | wall |
| --- | --- |
| `begin end.` (Pascal) | **0.25s** |
| `int main(void){return 0;}` (C) | **0.44s** |
| zero-byte `.npy` | **4.49s** |
| `test/test_nil_python_core.npy` — a real test | **4.59s** |
| `test/lib_mimic_xml_etree_elementtree.npy` — 288 lines, the biggest | **5.58s** |

A real NilPy test costs 4.59s against an empty file's 4.49s. **The test content
is free; the fixed tax is essentially the entire job.** One frontend pays ~4.2s
that no other frontend pays, for an empty file.

Isolating the units: a *Pascal* program whose whole body is `uses pylib;` costs
**2.93s**. So ~2.7s of the tax is `pylib.pas` (18,996 lines) alone, before
`pyeval.pas` (5,733) and the frontend's own setup.

### It is the largest single block in the matrix

`test-nilpy` is **719 of the full tier's 3,063 jobs (23%) and 70% of its CPU**,
mean 15.2s per job in the watcher's learned metrics. Paying the ~4.2s tax
**once** instead of 719 times removes **~3,016 CPU-seconds**. Against the
pre-hotspot-fix matrix that is 24%; against what remains after those fixes it is
a larger fraction still, because the fixes shrank the denominator too. The next
full tier at HEAD gives the real figure and I will append it rather than
extrapolate further.

### The scheduler is NOT the problem — a deliberate negative result

Same run: 12,319 CPU-seconds against 13,663 core-seconds available (2277s wall
× 6 cores) = **90% utilisation**. There is no meaningful parallelism to reclaim,
no serialisation to unpick, and ~1,343 idle core-seconds is close to the floor
for a job graph with dependencies. **Anyone optimising the matrix should not
start with the scheduler**, and I would rather record that than have the next
person measure it again.

### Why the tooling side cannot fix it

`--help` offers no precompiled-unit or unit-cache facility: `-Fu` adds a *search
root*, not a cache. So every invocation compiles those 24,729 lines from source
and there is nothing testmgr can do about it — a test harness cannot share an
artifact the compiler has no way to emit or consume. This ticket is the fix;
there is no tooling workaround to build in the meantime.

### The prio note

The owner's loudest standing complaint is that testing overhead is ~95% of
development time. This is the single largest identified block of pure repeated
work in the matrix, it costs no coverage to remove, and it is 4.2 seconds on
every NilPy user's hello-world as well. `prio: 45` looks low against that;
raising it is the coordinator's call, not T's, so this is a flag rather than an
edit.


## Re-prioritised 45 -> 85 by the coordinator, 2026-08-26

Track T measured this from the harness side and flagged the field rather than
editing it. Raising it, on the measurement and not on the opinion.

**It is ~70% of the test matrix.** `test-nilpy` is 719 of the full tier's 3,063
jobs -- 23% of the count, **70% of the CPU**. And the tax is not part of a NilPy
job, it IS the job: at HEAD, after the hotspot work, a zero-byte `.npy` costs
4.49s and a real 288-line test costs 5.58s. **The test content is nearly free.**
A Pascal program whose whole body is `uses pylib;` costs 2.93s, so ~2.7s is
`pylib.pas` (18,996 lines) before `pyeval.pas` or any frontend setup.

Paying that once instead of 719 times is **~3,016 CPU-seconds per full tier, at
zero coverage cost** -- and the same 4.2s lands on every NilPy user's hello-world,
so this is not only a test-harness concern.

**Peer of `feature-opt-o3-register-pressure`, also 85.** Between them they are
most of the matrix cost. The order between the two does not matter; both sit
below live segfaults and wrong-value bugs, which stay the owner's top rank.

**Why it is Track A's and cannot be worked around in the harness:** the compiler
offers no precompiled-unit or unit-cache facility -- `-Fu` adds a *search root*,
not a cache. A harness cannot share an artifact the compiler has no way to emit
or consume. Track T looked, found nothing to build on, and declined to invent
something that would look like progress. T owns the tool, never the bug.

**Recorded so nobody re-measures it: the scheduler is NOT the problem.** Same
run, 12,319 CPU-seconds against 13,663 core-seconds available (2277s x 6 cores)
= **90% utilisation**, ~1,343 idle core-seconds, near the floor for a job graph
with dependencies. There is no serialisation to unpick and no parallelism to
reclaim. Do not start with the scheduler.
