---
track: A
prio: 45
type: bug
status: done
owner: claude-A
---

# `VisCacheVis` is sized by the string-table constant — and the cap it is tied to is too low

- **Type:** bug (a constant load-bearing in two unrelated places, plus the
  capacity ceiling that exposed it — `compiler/defs.inc`, `compiler/symtab.inc`,
  `compiler/emit.inc`) — **Track A**
- **Found by:** Track C, csmith axis-3 sweep (seed 200056, `--paranoid`),
  [[feature-c-csmith-differential-fuzzing]]. Filed into A's lane rather than
  fixed under C: those three files are shared core.
- **Opened:** 2026-08-19.

## Read this first — the slug names the SYMPTOM, and the one-liner is a trap

The reported failure is a refused 14k-line program and the obvious fix is to
raise `MAX_STRS`. **Do not just do that.** `defs.inc:2378`:

```pascal
  VisCacheVis   : array[0..MAX_STRS] of Boolean;
```

It is indexed by **unit** (`declUnit + 1`, `curUnit + 1` in `symtab.inc`), not
by string. Units are bounded by `CompiledUnits`' 256 slots, so it is ~32x
oversized today and **cannot overflow — this is not a live correctness bug.**
But `symtab.inc:691` clears the whole array on every cache miss:

```pascal
  for i := 0 to MAX_STRS do VisCacheVis[i] := False;
```

and `VisibilityAllows` is called from every name lookup. So:

- **Raising `MAX_STRS` makes a hot-path clear proportionally longer**, for a
  reason that has nothing to do with strings. The one-line fix trades a loud
  refusal for a quiet slowdown, which is the worse of the two.
- **Decoupling the two pays off before any raise.** Sized by units instead, that
  clear gets ~32x cheaper than it is TODAY on an unmodified compiler.

That coupling is the actual defect. The cap is what made it visible.

## Symptom

```
pascal26:2: error: string table overflow
  near:       >>> unit builtinheap
```

The line number is a red herring — it names `builtinheap`, the compiler's own
injected unit, because by the time that unit is processed the table is already
full of the user program's literals. Nothing is wrong at line 2.

## Cause, measured

`compiler/emit.inc:258`, in `InternStr`:

```pascal
  if StrCount >= MAX_STRS then Error('string table overflow');
```

`MAX_STRS = 8192` (`defs.inc:15`). The seed-200056 program is 14125 lines with
**9426 distinct string literals** — over the cap by 15%. csmith's `--paranoid`
is what gets there: it emits a pointer assertion with its own message text at
every pointer operation, so literal count scales with the program rather than
staying flat the way hand-written C's does.

## The cap is an outlier, not a budget

Its neighbours in the same const block are `MAX_SYMS = 131072`,
`MAX_FIXUPS = 131072`, `MAX_PROCS = 16384`, `MAX_USES_EDGES = 16384`. 8192 is
16x below the symbol table it sits beside, and there is no comment justifying
it — unlike `MAX_CODE` three lines above, which carries the arithmetic of the
incident that raised it. Read this as a number nobody revisited.

## Measured fix, and the catch that makes it not a one-liner

Raising it to 65536 (one line) and rebuilding to a fixedpoint:

- seed 200056 compiles in **2.7s** and its checksum **agrees with gcc**
  (`F6AD3A62`), so the ceiling was the only thing wrong with that program.
- BSS grows ~1.4 MB — `Strs[]` is ~24 B/entry. Virtual only, same cost model as
  `MAX_CODE`.
- Self-compile of `compiler.pas`: 12.1 / 12.8 / 12.9 s raised, against
  11.1 / 11.8 / 13.3 s at 8192. **The difference does not separate from this
  box's noise**, so treat the compile-time cost of an 8x raise as "not measured
  above noise", NOT as "free" — see below for why it is not obviously free.

**The catch is `VisCacheVis`** — see the top of this ticket. An 8x raise makes
its hot-path clear 8x longer.

## Suggested shape — in this order

1. **Give `VisCacheVis` its own constant sized by units** (`MAX_UNITS`-ish,
   256-512), decoupling it from the string table entirely. This is the fix;
   everything else is the capacity bump that exposed it. Worth doing on its own
   merits even if step 2 is never done.
2. Then raise `MAX_STRS` — with a comment carrying this arithmetic, in the style
   `MAX_CODE` already uses.
3. Optional, only if a measurement asks for it: `InternStr` is a linear scan of
   every interned string per intern (`emit.inc:245`), i.e. O(n²) in distinct
   literals. At 9426 that is ~44M string compares and did not show up above
   noise, so this is a note for whoever raises the cap much further, not work to
   do now.

Doing 2 without 1 trades a loud refusal for a quiet slowdown, which is the worse
of the two.

## Repro

```sh
tools/csmith_fuzz.py --seed 200056 \
  "--csmith-args=--paranoid --max-pointer-depth 4 --max-struct-fields 15 --max-union-fields 8 --max-array-dim 3"
```

Or generate any C file with >8192 distinct string literals.

## Gate

`make test` + self-host fixedpoint (this changes a core constant and an array
size, so the fixedpoint is the real check), plus seed 200056 compiling and
agreeing with gcc. Measure the `compiler.pas` self-compile time before and
after on an idle box — the point of step 1 is that it should get FASTER, not
merely not-slower.

## Resolution (2026-08-21)

Both steps, in the order the ticket asked for.

### 1. `VisCacheVis` is sized by units now

`array[0..MAX_UNITS]` (257 slots) instead of `array[0..MAX_STRS]`, with a new
`MAX_UNITS = 256` naming the ceiling `ParseUnit` already enforces at
`if CompiledUnitCount < 256`. The hot-path clear in `VisibilityAllows` — run on
every cache miss, from every name lookup — went from **8193 iterations to 257**,
and would have gone to 65537 had step 2 landed alone.

Added with it: an explicit out-of-range arm in `VisibilityAllows` that answers
from the edge table directly instead of indexing the cache. It is unreachable
today; it is there so that raising the unit cap is a one-line change rather than
a silent out-of-bounds read, which is the failure the old coupling stood one
step away from.

### 2. `MAX_STRS` 8192 → 65536

With the arithmetic in a comment, in `MAX_CODE`'s style.

### Measured

**The repro reproduces, and the fix fixes it.** A generated C program with 9500
distinct literals, against the binary from before this change and after:

```
old: pascal26:2: error: string table overflow / near: >>> unit builtinheap
new: ok   46146250        gcc -O0 oracle: 46146250
```

Note the old error names line 2 and an injected unit — exactly the misleading
message in the report, reproduced.

**On the self-compile timing, the honest answer is "no signal".** Three runs
before and three after suggested 26.7s → 21.8s, but interleaving the two
binaries under the same load gave 24.8/26.4/28.9 (before) against
26.4/28.9/28.0 (after), with load climbing through the run — Track T is on this
box. So: **the 8x raise did not make the self-compile measurably slower, and the
claimed speedup does not survive an interleaved measurement.** The argument for
step 1 is the iteration count above, which is arithmetic, not a wall-clock
claim.

### Not done

Step 3 (`InternStr`'s linear scan, O(n²) in distinct literals) is deliberately
left alone — the ticket flagged it as a note for whoever raises the cap much
further, and at 9500 literals it does not show above noise. It stays a note.

### Regression guard

`tools/gen_manylit_c.py` generates the program into `TESTTMP` and the C block
compares against gcc. Generated rather than committed: the point is the COUNT,
and a 9500-line source in `test/` would be 9500 lines of noise. The generated C
is free of backslash escapes on purpose — they would have to survive make, the
shell and python quoting in that order, and the first draft lost one layer and
produced a source gcc could not parse.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 110s — the real check here,
since this changes a core constant and an array size). 9500-literal C program
compiles and matches the gcc oracle; the pre-change binary refuses it. csmith
seed 200056 itself was not re-run (csmith is not installed on this box); the
generated program reproduces the same ceiling.

## Log
- 2026-08-21 — resolved, commit c7e6a86ca.
