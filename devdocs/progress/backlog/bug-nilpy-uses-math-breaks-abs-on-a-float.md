---
track: A
prio: 50
type: bug
blocked-by: []
summary: "Pulling lib/rtl/math into a NilPy program breaks `abs` on a float — ambiently it stops COMPILING (`candidates: abs(LongInt)`), non-ambiently it compiles and answers wrong: `abs(-0.0)` gives -0.0 and `abs([-0.0][0])` gives 6642640, a pointer read as a number. It is what blocks routing `**` at the RTL's correctly-rounded Power."
---

# `uses math` in a NilPy program breaks `abs` on a float

Found 2026-08-16 while prototyping
[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]], whose fix needs the
`math` unit linked so `**` can reach the RTL's `Power`.

## Repro

Any `.npy` where the compiler pulls `math`, then:

```python
print(abs(-1.5))
print(abs(-0.0), abs([-0.0][0]))
```

Two different failures depending on HOW the unit is pulled:

| pull | result |
| --- | --- |
| `ParseUsesUnitAmbient('math')` | compile error: *no overload of abs matches these arguments; argument types: (Double); candidates: abs(LongInt)* |
| `ParseUsesUnit('math')` | compiles, and `abs(-0.0)` = `-0.0` (CPython: `0.0`), `abs([-0.0][0])` = **6642640** |

`test/test_nilpy_abs_minmax_sum_oracle.npy` catches both.

The second row is the serious one: a pointer value printed as a number, with no
diagnostic. A variant-held float reaching an integer `Abs` is the likely shape —
the same family as
[[project_nilpy_byname_findproc_lowerings_are_the_unchecked_population]].

## Not the last-named-unit rule

Pulling `math` BEFORE `pylib`/`pyeval` instead of after changes nothing, so this
is not scope hiding picking the wrong unit. `math.pas` declares
`Abs(Integer)` first and `Abs(Double)` fourth, which is exactly the shape
`FindProcArityDouble` exists to work around for `math.pow` — so a by-name
`FindProc('abs')` somewhere in the NilPy lowering is the first place to look.

## One arm is already half-fixed

An EXPLICIT `import math` plus `abs(-1.5)` **compiles and answers correctly on
HEAD** and FAILS on the pinned binary — the visibility work landed 2026-08-15
(non-transitive `uses` + scope hiding across the six name tables) fixed that
arm. The implicit/ambient arm and the wrong-VALUE arm are still open, and the
wrong-VALUE one is not a visibility bug at all.

## Why it matters beyond `abs`

`math.pas` also declares `Min`, `Max`, `Round`, `Floor`, `Ceil`, `Sqrt`, `Exp`,
`Ln`, `Power` — every one of which NilPy also has a builtin for. `abs` is simply
the first one a test happened to cover. Whatever fixes it should be checked
against the whole set, not just the one name.

## Blocks

[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]] — its prototype is
measured (78 → 107 exact rows of 120, worst error 84 ulp → 1 ulp) and kept at
`devdocs/dev/prototypes/nilpy-float-pow-via-rtl-power.patch`, waiting on either
this or a private builtin unit carrying Power's kernels.
