---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`x: float` in a plain class body is parsed, accepted, and its TYPE thrown away, so every read of the field is a variant; the identical two lines under `@dataclass` type it correctly. Measured 25.8x on arithmetic over such fields."
---

# A class-level field annotation is discarded unless the class is a dataclass

The same declaration, one decorator apart, measured 2026-09-15 at
`4452ec0631a97c02`:

```python
@dataclass
class V:
    x: float
    y: float

class P:                 # the SAME declaration, no decorator
    x: float
    y: float
    def __init__(self, x, y):
        self.x = x
        self.y = y
```

`PXXDBG=n.locals` on `q = v.x * 2.0`:

| receiver | `q` |
| --- | --- |
| `r_v(v: V)` — dataclass | `tk=19` (double) |
| `r_p(v: P)` — plain class | `tk=22` (variant) |

The program RUNS CORRECTLY either way and matches CPython, so nothing is wrong
with the value. What is lost is the type, silently, and with it the arithmetic.

## Why it costs what it costs

A variant-typed local is not a slower double; it is a different execution mode.
Measured the same evening, `$SCRATCH/va4.npy`, min-of-3 interleaved, both arms
the SAME loop shape — three plain local reads on each side, no subscripting
anywhere, so only the arithmetic differs:

```
variant 0.9466 s
double  0.0367 s
ratio   25.81x      <- WRONG, see below
```

**THAT NUMBER IS CONTAMINATED AND SO WERE THE TWO BEFORE IT. THE CLEAN FIGURE
FOR THIS SHAPE IS ~156x.** Three successive benchmarks, three defects, all mine
and all in the DESIGN rather than the timing:

1. *"50-100x"* — quoted to a peer from expectation, never measured.
2. *2.7x* — INERT: `ax = 0.0` is inferred as a double with no annotation, so both
   arms compiled identically. `PXXDBG=n.locals` showing `tk=19` on BOTH arms
   caught it.
3. *25.81x* — the loop was `while i < n` with `n` an UNANNOTATED PARAMETER, so
   the variant arm paid **a heap allocation per iteration** for the comparison
   (see below). It measured arithmetic PLUS malloc/free.
4. *172x* — bound annotated, but `px * 1.5 - py * 0.5` is LOOP-INVARIANT and the
   native arm hoists it while the variant arm does not, so the double arm got 7x
   faster on work it stopped doing (0.0367 -> 0.0052 s).

With the bound annotated on both arms AND every operation loop-carried so
nothing is hoistable — 3 multiplies and 3 adds per iteration, 300k iterations,
min-of-3 interleaved:

```
variant 0.4736 s
double  0.0030 s
ratio   156.0x
```

Allocation census confirms the contamination is gone: ~196 allocations total,
constant, against 185433 for the same iteration count in the `while i < n` form.

**AND A SEPARATE, SHARPER FINDING FELL OUT OF FIXING IT: A VARIANT COMPARISON
ALLOCATES, A VARIANT ARITHMETIC OPERATION DOES NOT.** Isolated by census
(`-dPXX_ALLOC_CENSUS`), 100k iterations:

| loop body | 32-byte allocations |
| --- | --- |
| variant arithmetic only (bound annotated) | none — below the census threshold |
| variant comparison only (`if i < v`) | **91466** |
| neither | none |

One block per comparison evaluated, linear in the iteration count. Filed as
`bug-n-a-variant-comparison-heap-allocates-a-box-per-evaluation`. It is
corroborated independently by the lekkerzeilen seat's sampling profile, whose
top leaves on an unannotated loop were `pycmp_v`, `PXXPromoVarCmpTry`,
`PXXPromoToVariant`, `PyOrdCheck` and `PXXAlloc`/`PXXFree` — two instruments
that share nothing agreeing on the same mechanism.

**AND THAT FIGURE DOES NOT YET EXPLAIN ANY REAL PROGRAM — A DIRECT TEST OF IT
CAME BACK NULL.** Measured on lekkerzeilen the same evening: removing 11 of 41
variant locals from the hot path (the whole `arm`/`world`/`flow`/`v`/`w` family
the integrator touches every contributor every tick) produced two clean paired
rounds that **DISAGREE IN SIGN**:

    round 1   unannotated 2.10 fps / 126.4 vsteps   defs-annotated 2.06 / 123.7
    round 2   unannotated 2.18 / 130.5              defs-annotated 2.25 / 134.8

Stated that way deliberately, at the measuring seat's own insistence: the first
write-up here said "+3%", which reads like a small effect, and **two rounds
disagreeing in sign is what a null actually looks like.** Removing 11 of 41
hot-path variant locals does not move throughput in a direction anyone can name.
A third interleaved round was lost to a broken wait-guard and is not counted.

The 25.8x is a real property of a tight arithmetic loop and is NOT a claim about
what variants cost in situ. Two honest reasons it can be both: a 27% cut in the
COUNT of variant locals is not a 27% cut in variant OPERATIONS EXECUTED, and the
30 that remain include the contributor loop variable itself. But the conclusion
to write down is the negative one: **the cost of the demo's hot path is not yet
explained, and no ticket may be ranked as if variant dispatch explained it.**
An interleaved repeated measurement is running to replace the point estimate
with a bound.

**The route was forced through an unannotated PARAMETER, and that detail is the
whole measurement.** The first attempt at this benchmark wrote `ax = 0.0`
unannotated and measured 2.7x — because the inference types a float-literal
local as a double with no annotation at all, so both arms compiled to the same
code and the probe never reached a variant. `PXXDBG=n.locals` showing `tk=19` on
BOTH arms is what caught it. CLAUDE.md's "isolation guards the RUN, not the
ROUTE", arriving by the front door.

## Where the type goes

`PyClsAttrEqIdx` (`pyparser.inc`) steps OVER the annotation to find the `=` that
binds the attribute, and returns only that index — the annotation is read for
SYNTAX and its type is never asked for. Its own comment records that this shape
used to fail to parse at all, and that `@dataclass` was the one reader that
accepted it, through its own field branch
(`bug-nilpy-annotated-class-attribute-fails-to-parse`).

That dataclass branch is the `else if isDC and ... (Tokens[i + 1].Kind = tkColon)`
arm of the class-body loop in `pyparser.inc` (grep `@dataclass field: name :
annotation`) — cited by name because a line number here goes stale pointing at a
real line that explains nothing. It does
the right thing — `tk := PyAnnTypeAt(j)`, then `AddUField(..., Ord(tk), ...)` —
including `tyClass` fields via `PyAnnLastCi`, `Callable[...]` signatures via
`PyAnnLastProcSig`, and the `tyUnknown` -> variant degrade. **Everything the
plain-class case needs is already written; it is behind a decorator test.**

The neighbouring branch (an attribute WITH an initialiser, `n = 0`) infers `tk`
from the RHS and registers the field. A plain class's annotation-only line
(`x: float`, no `=`) matches neither: not the initialiser branch, which needs the
`=`, and not the dataclass branch, which needs `isDC`. It falls through, and the
field is created later from `self.x = x` in `__init__` — at the PARAMETER's type,
which for an unannotated parameter is a variant.

So this is the `normalise-dont-special-case.md` shape exactly: one concept, two
readers, and the second one stays broken. The fix is to drop `isDC` from the
annotation-only arm rather than to grow a third path.

## What is NOT broken — measured, so nobody re-derives it

Six of seven ways to give a field a type already work. Only the class-level
annotation is discarded:

| how the field is typed | read off an annotated param |
| --- | --- |
| `__init__(self, x: float)` then `self.x = x` | `tk=19` |
| `self.x = 0.0` (literal in ctor) | `tk=19` |
| `self.x: float = x` (annotated at the store) | `tk=19` |
| `self.x = float(x)` | `tk=19` |
| `self.x = x * 1.0` | `tk=19` |
| `@dataclass` + `x: float` | `tk=19` |
| **`x: float` in a plain class body** | **`tk=22`** |
| `__init__(self, x)` then `self.x = x` | `tk=22` (correct — nothing declares it) |

And parameter annotations DO propagate, contrary to what the symptom suggests:
`def f(a: float, b: float): q = a + b` gives `q tk=19`, `int` gives `tk=28`, and
unannotated gives `tk=22`. A two-hop chain `s.position.x` through an annotated
`s: State` types correctly too — **provided the field at the end was typed by one
of the six working routes.** The reader's annotations are necessary and not
sufficient; the declaration site is what decides.

## Why it is ranked here

Found 2026-09-15 while answering the lekkerzeilen seat's question about what
costs 4.9 ms in one `Vessel.step`. 41 of that demo's hot-path physics locals are
`tk=22`, and the seat had annotated ten method signatures to no effect — correctly,
because the variance is at the value types' declaration sites, not at the readers.

**AND THIS TICKET IS NOT THAT DEMO'S FIX — MEASURED, BECAUSE THE PROVENANCE
ABOVE READS LIKE A CAUSE AND IS ONLY A ROUTE.** An AST census of the whole
lekkerzeilen tree finds **zero** class-level `AnnAssign` in any class body and
**zero** `@dataclass`. The idiom this ticket is about does not appear in the
demo at all, so it explains none of the 41. Those come from unannotated
`__init__` parameters — the LAST row of the table above, which is the compiler
being correct. This ticket is a separate defect found on the way there, and
ranking it on the demo's frame rate would be ranking it on a connection that
does not exist.

**AND THE CONSTRUCTOR IS NOT THAT DEMO'S LEVER EITHER — I SAID IT WAS AND IT
BOUGHT ZERO.** Measured by the lekkerzeilen seat on the real file: three
`Vec3.__init__` parameter annotations moved the hot-path `tk=22` count from 41
to 41, and annotating `State`'s field stores as well moved it to 41 again. Four
RETURN-TYPE annotations moved it to 26. The reason is the caller's shape, not
the value type's: **a constructor types a FIELD, which helps a reader that reads
the field; a reader that CALLS A METHOD needs that method's return type
instead.** My fixture read `v.x`, their physics calls `state.to_world(probe)`,
and I generalised from the one to the other without checking. Both routes are
real and which one pays is a property of the CALLER — see
`bug-n-annotating-a-local-that-is-returned-destroys-the-defs-inferred-return-type`
for the return-type surface and its two blind spots.

It is the canonical Python idiom for declaring a field's type, it is what
`@dataclass` itself requires, and a user who writes it gets no speedup, no
diagnostic, and nothing to tell them the decorator was the load-bearing part.

## Residual question, owned by this ticket

Whether dropping `isDC` is sufficient or whether the annotation-only line also
has to suppress the later `self.x = x` registration in `__init__` — if both run,
`FindUField` already guards the duplicate, but the ORDER decides which type wins
and that has not been measured. Check it before assuming the guard is enough.
