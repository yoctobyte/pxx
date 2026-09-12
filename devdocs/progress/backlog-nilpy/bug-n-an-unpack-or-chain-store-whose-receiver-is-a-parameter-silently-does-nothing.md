---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`def f(b): b.s, b.t = 22, 23` COMPILES, RUNS, prints nothing and STORES NOTHING — the fields keep their initial values. Any store through PyUnpackTargetStore (the TUPLE UNPACK and CHAINED-ASSIGNMENT paths, which share it) is silently dropped when the receiver is a PARAMETER. MEASURED 2026-09-12 against the PINNED compiler and HEAD, identical on both, so it is pre-existing and not from the chain widening landed the same day. THE SAME STORE WRITTEN AS A SINGLE STATEMENT IS CORRECT (`b.s = 11` works), and a LOCAL or MODULE-LEVEL receiver is correct (`a.s, a.t = 31, 32` works) — so the defect is exactly PyUnpackTargetStore + parameter. NO DIAGNOSTIC, and the value it leaves behind is the field's initial value, which is plausible. Found only because a chain fixture happened to use a parameter; the receiver kind a test naturally uses is the one that works, because a test constructs the object where it uses it."
---

# An unpack or chain store through a parameter receiver is silently dropped

Found 2026-09-12 while widening `PyParseChainAssign` to nested attribute targets.
Not caused by that work — the pin behaves identically.

## The measurement

```python
class A:
    def __init__(self):
        self.s = 0
        self.t = 0

def single(b):  b.s = 11;            print(b.s)        # 11   CORRECT
def unpack(b):  b.s, b.t = 22, 23;   print(b.s, b.t)   # 0 0  WRONG (CPython 22 23)
def chain(b):   b.s = b.t = 33;      print(b.s, b.t)   # 0 0  WRONG (CPython 33 33)
```

| receiver | single stmt | unpack / chain |
| --- | --- | --- |
| `self` | ok | **ok** |
| local (`a = A()` in a def) | ok | **ok** |
| module-level name | ok | **ok** |
| **PARAMETER** | ok | **STORES NOTHING** |

Pinned compiler and HEAD give the same wrong answer on the unpack row, so the
range is older than either. The chain row cannot be compiled by the pin at all
(chained assignment postdates it), which is why the unpack row is the one to
quote.

## Why it survived

**No diagnostic, and the residue is the field's initial value** — `0`, or
`False`, or whatever `__init__` set. Nothing looks wrong at the call site and
nothing looks wrong in the output unless you know the expected number.

**And the arrangement that exposes it is the one nobody writes.** A test that
exercises tuple unpacking onto attributes constructs the object in the same
function it uses it in, so the receiver is a LOCAL — which works. Passing the
object in as a parameter and unpacking onto it there is the uncommon spelling.
This is the same shape as the first-wins ordering family in CLAUDE.md: the
passing arrangements are not a sample, they are the population everyone writes.

## Where to look

`PyUnpackTargetStore` (`compiler/pyparser.inc`) resolves its receiver from
`PyProgSym(nm)` and the symbol's class identity. Compare against what the
SINGLE-statement path builds for the same source — that one is correct, so the
difference between the two receivers' resolution is the whole bug. Suspect the
parameter symbol's `RecName` being unset where a local's is set, which would send
the store to the dynamic setter while the READ stays on the declared field — the
two would then disagree exactly as measured.

**Positive control when fixing:** the table above, with the parameter row
asserted to the CPython value. A fixture using only `self`, a local or a
module-level receiver passes today and certifies the bug.
