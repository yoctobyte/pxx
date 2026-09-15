---
track: N
prio: 75
type: bug
blocked-by: []
summary: "Annotating an operator dunder's operand (`def __add__(self, o: 'V')`) makes the operator raise `TypeError: expected a number, got object` whenever the RECEIVER is a variant. Bare works, annotated raises, matched pair one character apart. The annotation is the biggest codegen win we have measured, so it is a trap."
---

# Annotating a dunder operand breaks the operator on a variant receiver

Two programs, byte-identical except for one annotation:

```python
class V:
    def __init__(self, x):
        self.x = float(x)
    def __add__(self, o):          # vs.  def __add__(self, o: 'V'):
        return V(self.x + o.x)

class H:
    def __init__(self):
        self.a = V(1.0)
        self.b = V(2.0)

def known_receiver():
    a = V(1.0); b = V(2.0)
    c = a + b
    return c.x

def variant_receiver(h):           # h is bare, so h.a is a VARIANT
    c = h.a + h.b
    return c.x
```

```
bare        known_receiver 3.0   variant_receiver 3.0                      rc=0
annotated   known_receiver 3.0   TypeError: expected a number, got object  rc=217
CPython     3.0                  3.0
```

**Known receiver: correct both ways. Variant receiver: correct bare, raises
annotated.** The temporary is bound to a local on purpose — `(a + b).x`
segfaults on its own account
(`bug-n-attribute-access-directly-on-a-dunder-result-segfaults`) and would mask
this.

## The raise

`PyTypeError(p^.VType, 'a number')` in `pyvar_to_float`, `pylib.pas:9433` — the
generic variant-add arm taking the NUMERIC path with an object operand. `pylib`
carries roughly twenty comment blocks describing this same message from this
same cause, all of the form *"numeric path and raised 'expected a number, got
object' for a dunder the ..."*, so the arm is known to be the fragile one.

The mechanism, stated as a guess and marked as one: **the annotated dunder no
longer matches whatever the variant dispatch matches on**, so dispatch falls
through to the numeric arm. Nobody has read that matching code yet.

## Why it matters more than an ordinary dispatch bug

The operand annotation is the largest single code-generation improvement
measured on this compiler. On real code (`feature-n-specialise-a-dunder-body-...`):

```
Vec3.__add__   6260 B, 210 calls, 0 SSE  ->  873 B, 18 calls, 3 SSE
```

**And in real programs a receiver is a variant most of the time** — off an
unannotated parameter, a container element, or a field of an untyped object. A
demo-wide census found 95 classes, 82 constructors, **334 constructor
parameters, ZERO annotated**, which is simply how Python is written.

So the annotation that produces that code generation is the same annotation that
breaks the operator at most of the call sites that would benefit — and the
runtime message points nowhere near the edit the user made. A user following the
advice gets a program that is beautiful in the disassembly and dies at run time.

## It is NOT a blocker, because the safe cut is measured

Five arms, one compiler sha, guard satisfied:

```
arm       Vec3.__add__   Quat.rotate
b_no              6260         24674
b_op               873          2175   <- CRASHES
b_op2             6260          2175   <- runs
```

`b_op2` annotates nine NON-dunder method parameters. **It gets the entire
`Quat.rotate` win — 24.7 kB to 2.2 kB — and the program runs.** The dangerous
annotation bought only `Vec3.__add__`, which that program barely executes.

**So the shippable guidance is: annotate method parameters and constructor
parameters; leave operator dunders bare until this is fixed.** No caveat a user
has to interpret. That is what should go in the NilPy docs, and it is why this
sits at 75 rather than blocking the guidance.

## Likely one fix, not two

If the variant dispatch consulted the annotated signature the way the static
path does, both the crash and the code-generation win would come from the same
place, and the operand annotation would become a real recommendation instead of
a trap.

Found 2026-09-15 by the lekkerzeilen seat, by building the matched pair rather
than accepting the advice. Its own demo arm died after exactly one frame on this
bug, in `Camera._chase`:
`state.position + behind * self.distance` with `state` a bare parameter.

## The mechanism, read rather than guessed — and it is one line

`PyUserArithCall1` (`compiler/builtin/pylib.pas`), the single runtime call every
arithmetic, in-place and `__getitem__` dunder goes through when an operand's
static type is a variant:

```pascal
  pk := PInt64(mi^.ParamKinds);
  if pk[1] <> 22 then Exit;               { `other` must be a Variant }
```

An annotated `other` is not kind 22 — `o: 'V'` is a class pointer (6), `k:
float` a Double (19), `i: int` an Int64 (13) — so the dispatch DECLINES the
dunder, `PyVarUserArith` answers False, and the caller's numeric arm raises
`expected a number, got object` about an operand it was never meant to see.
**`o: float` fails identically** (measured: `def __add__(self, o: float)` with
`h.a + 2.0` on a bare `h`, rc=217), so the class shape was never special; the
guard is the whole bug. The type block above it says why it was written that
way: *"unlike __eq__ there is no dataclass-GENERATED arithmetic dunder to
produce the class-pointer shape"* — true, and hand-written annotations produce
it every day.

`__eq__` already had the class-pointer arm (`TPyEqObjFn`), with an exact-class
check that CPython's own dataclass `__eq__` performs. Arithmetic has no such
rule in CPython, and the RTTI records a parameter's KIND but not its class, so a
cross-class check would refuse `Quat.__mul__(self, v: 'Vec3')`; the compiled
method-call path on a variant receiver already hands an instance to a
class-typed parameter by TAG alone, and this follows it.
