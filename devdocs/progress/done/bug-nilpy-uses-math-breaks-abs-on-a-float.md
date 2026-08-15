---
track: A
prio: 50
type: bug
blocked-by: []
summary: "Pulling lib/rtl/math into a NilPy program breaks `abs` on a float — ambiently it stops COMPILING (`candidates: abs(LongInt)`), non-ambiently it compiles and answers wrong: `abs(-0.0)` gives -0.0 and `abs([-0.0][0])` gives 6642640, a pointer read as a number. It is what blocks routing `**` at the RTL's correctly-rounded Power."
status: done
owner: agent-acpn
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

## FIXED 2026-08-16 — abs/sqr; min/max split out

### The gate was the bug

`Abs`/`Sqr` lower to builtin helpers at one site in ParseFactor, and that site
was gated `procIdx < 0` — "no routine of this name resolved". In Pascal that is
exactly right (a user routine shadows a System intrinsic). In NilPy it is
wrong: `abs` is a Python BUILTIN, and whether it keeps its meaning must not
depend on what a pulled Pascal unit happens to declare. `import math` links
lib/rtl/math, `abs` resolved, the whole intercept was skipped, and overload
resolution answered instead — with math's `Abs`, whose float arm is
`if x < 0 then -x` (so `-0.0` comes back unchanged) and whose Integer arm ate a
variant and printed its payload as a number.

The gate is now `procIdx < 0` **or** (NilPy user code and the resolved routine
was declared in a DIFFERENT unit). A NilPy `def abs(x)` of the user's own is
declared in their own unit (or the main program, index -1) and still shadows —
pinned in the test. Pascal parsing is untouched: `NilPyUserCode` is false there,
so the gate stays exactly `procIdx < 0` and the self-host build is
byte-identical.

Both reported arms are gone, including the wrong-VALUE one:

```
import math
print(abs(-1.5), abs(-0.0), abs([-0.0][0]), abs(-3))
1.5 0.0 0.0 3          <- CPython's answer, was: 1.5 -0.0 6626872 3
```

### What is NOT fixed, and it is a different bug

`min` and `max` have the same disease and CANNOT be cured the same way — they
have no intrinsic intercept, they go through ordinary overload resolution over
a deliberately rich candidate set. With math linked, `max(1.5, 2)` answers
`2.0` where CPython answers `2`: math's `Max(Double, Double)` wins and the int
argument loses its type. Split out as
[[bug-nilpy-import-leaks-the-units-names-into-the-python-namespace]], which is
the ROOT this ticket only treated locally: Python's `import math` binds the NAME
`math`, it does not put `abs`/`min`/`max`/`round`/`floor`/`sqrt` into the
importing module's namespace. NilPy implements the import as `ParseUsesUnit`,
which does. Fixing that once covers every name on the list this ticket's "why it
matters beyond abs" section names, instead of one intercept at a time.

### Gate

`make compiler/pascal26` (self-host fixedpoint, byte-identical) + `tools/gate.sh
quick` GREEN. `test/test_nilpy_abs_under_import_math.npy` pins it against
CPython: the two wrong values, a variant from a loop, an unannotated parameter,
Sqr (which shares the gate), and the user's own `def sqr` still shadowing.

### Unblocks

[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]] as far as `abs` goes.
Its prototype pulls math AMBIENTLY, and the ambient arm's failure was the same
overload-resolution answer reported as a compile error — the intercept now runs
before resolution is consulted at all. Whoever picks that ticket up should
re-apply `devdocs/dev/prototypes/nilpy-float-pow-via-rtl-power.patch` and
re-measure rather than assume; the min/max half above is still live under it.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
