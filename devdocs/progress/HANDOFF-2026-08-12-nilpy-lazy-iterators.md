# Handoff prompt — NilPy lazy iterator objects (Track N)

Written 2026-08-12 for a fresh context. Paste the block below as the opening
message. Everything it needs beyond that is in the two tickets it names.

---

You are on **Track N (Nil-Python frontend)**, working directly on `master`.

Implement **`feature-nilpy-lazy-iterator-objects`** — the umbrella for making
`map` / `filter` / `enumerate` / `zip` / `reversed` return real lazy cursor
objects instead of eager lists.

**Read first, in this order, and do not re-derive what they already measured:**

1. `devdocs/progress/backlog/feature-nilpy-lazy-iterator-objects.md` — the
   umbrella: landing order, the six acceptance rows, the landmines.
2. `devdocs/progress/decided/decide-nilpy-eager-map-filter-reversed-enumerate.md`
   — the decision and every measurement behind it, including the model in one
   table.

**The short version of why.** CPython's `map` is a class whose instances are
cursors: `m = map(f, xs)` runs `f` zero times, breaking a loop early parks the
cursor, and resuming continues from there. pxx returns a list — Python 2's
`map`. The consequence that makes this a correctness ticket: with an early
`break`, `f` runs for every element, so a function that raises past the break
point crashes a program CPython runs fine. That program is in the decide ticket
and is the acceptance test for the whole umbrella.

**Land it in the umbrella's four steps, each independently green and pushed.**
Do not hold a long-lived broken state, and do not start step 3 before steps 1
and 2 are in. One builtin per commit in step 3 — a regression is far easier to
place that way.

**Before you switch any builtin**, do the check the umbrella calls the
"behaviour removal": `len(map(...))` answers `2` here today and is a
`TypeError` in CPython. Grep `test/*.npy`, `examples/**` and `lib/**` for
`len(` applied to a `map`/`filter`/`zip`/`enumerate` result and decide
deliberately what happens to any hit.

**Gate, per step** — this is the whole gate, do not widen it:

```
make compiler/pascal26        # ~12s, and it IS the byte-identical fixedpoint
<your repro>
tools/gate.sh quick           # ~30s
make test-nilpy               # the family sweep — required, this is variant lowering
make stabilize-fast && make pin   # pylib is compiler/builtin
git commit && tools/sync.sh
```

`make test-nilpy` takes ~20-40 minutes: **start it in the background and keep
working**, do not poll it. Resolve tickets with `tools/progress.sh resolve
<slug>` and no sha — `tools/sync.sh` fills in the one the commit landed as.

**Four landmines this work walks straight into.** The umbrella has the detail;
these are the ones that will cost you a day if you meet them cold:

- A stored callable is the hazard. `map` keeps `f` inside the cursor, and a
  callable has three representations here — crossing them writes a variant tag
  into a pointer slot and faults far from the cause. A lambda is a fourth shape
  (an interpreted pyeval source closure). Test `map` with a `def`, a lambda, a
  bound method and a builtin (`str`) before you believe it works.
- The shell pre-pass and the body pass must agree on any return type you touch;
  a disagreement is a silent ABI mismatch, not an error.
- `make test-nilpy` is the only thing that sees variant-lowering regressions —
  `gate.sh quick` will be green while the suite is red.
- pylib lives in `compiler/builtin`, so a change there needs the pin, not just
  a commit.

**Method that has been working on this track:** write realistic little programs
(30-120 lines that do something real) and diff them against CPython — that is
how this ticket was found and how its severity was measured. `python3 prog.npy`
is the oracle; a `.npy` file is valid Python.

When a step is green, resolve nothing but that step; the umbrella closes when
the six acceptance rows in it all match CPython.
