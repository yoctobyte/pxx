---
track: A
prio: 45
type: perf
blocked-by: []
summary: "The structural half of bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost, which halved the constant (8.62s -> 4.06s) by removing the hotspots but did NOT remove the WORK: every .npy compile still parses and code-generates all 24,460 lines of pylib.pas + pyeval.pas before it looks at the user's program. A zero-byte .npy costs 4.06s where `begin end.` costs 0.24s."
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
