---
track: N
prio: 65
type: bug
---

# `C.attr` on a class attribute: "class method not found"

- **Type:** bug (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
class C:
    count = 0
print(C.count)          # error: class method not found: count
C.count = 5             # same
```

and inside a method, which is the idiom that matters:

```python
class C:
    count = 0
    def __init__(self):
        C.count += 1    # error: class method not found: count
```

**Every** access through the CLASS NAME fails — read, write, augmented, at
module level or inside a method.

## What DOES work

```python
class C:
    n = 5
c = C()
print(c.n)              # 5     via an INSTANCE
print(C().n)            # 5
class D:
    n = 7
    def get(self):
        return self.n   # 7     via self
a, b = C(), C()
print(a.n, b.n)         # 5 5   shared read
```

So class attributes exist and read correctly through an instance. Only the
`ClassName.attr` route is missing — and with it the counter/registry idiom,
which is the main reason to write a class attribute at all.

## Cause — TWO parts, and they are not equally hard

**1. The lookup never checks.** `parser.inc:4399` handles `ClassName.member`:
it tries methods, then class-ref operations (`InheritsFrom`, `ClassName`), then
errors. It never consults the class-attribute storage. Proof that this is a
real, separate half: an attribute with a NON-literal initialiser DOES get a
hidden global (`PyClsAttrGlobalName` → `$clsattr.<Class>.<name>`, built by
`PyEmitClassAttrExpr`), and `C.n` fails for it anyway:

```python
class C:
    n = 2 + 3        # gets a real global
print(C.n)           # still: class method not found: n
```

So for non-literal initialisers this is a **lookup-only fix**: fall back to
`FindSym(PyClsAttrGlobalName(ci, fieldName))` before erroring.

**2. A LITERAL initialiser has no storage to find.** `count = 0` is folded as a
constant into the field default — `PyEmitClassAttrExpr`'s own comment says the
single-literal case "is the folded-constant case the pre-pass already took". So
there is no global to point at, and `C.count = 5` has nowhere to write.

Making the common case work therefore needs literal class attributes promoted to
real storage, which is the risky half: it changes how every class attribute is
laid out and interacts with dataclass defaults (`PyDc*`) and instance init.

## Suggested order — CORRECTED 2026-08-02, I tried part 1 and REVERTED it

My first read was that part 1 is small and safe because "the literal path errors
today either way". **That is wrong, and the counter-example is recorded here so
nobody repeats it.**

The lookup fallback was implemented — `FindSym(PyClsAttrGlobalName(ci,
fieldName))` before the error at `parser.inc:4399`, returning an `AN_IDENT` on
the hidden global. It builds, self-hosts, and works in the obvious cases:

```python
class A:
    n = 2 + 3
print(A.n)        # 5   read      ok
A.n = 9           #     write     ok
class A:
    n = 0 + 0
    def bump(self): A.n += 1      # ok, in a plain method
A(); print(A.n)   # 1   in __init__, bare construction   ok
```

Then this, which differs only in binding the instance to a name:

```python
class A:
    n = 0 + 0
    def __init__(self):
        A.n += 1
class B:
    m = 2 + 3
a = A()           # <-- assigned, rather than a bare A()
print(A.n)        # CPython 1     with the fix: 0     SILENTLY WRONG
```

`A()` bare gives 1; `a = A()` gives 0 — the constructor's side effect on the
class attribute is lost. Other arrangements of the same program instead failed
to compile with "assignment target is not an lvalue". So the fallback interacts
with the constructor/hoisting path in a way that is not understood, and it turns
a loud, correct refusal into a SILENT WRONG VALUE, which is the worst outcome
this repo recognises. Reverted.

**Whoever picks this up: the lookup fallback alone is not sufficient and not
safe.** The interaction to understand first is why the class-attribute global
misses the constructor's write when the result is bound to a name — most likely
the hoisted `$clsattr` initialiser assignment running relative to the
constructor call, not the lookup itself. Get that right, then parts 1 and 2
can be judged.

## 2026-08-02 — THE ABOVE DIAGNOSIS IS WRONG. Measured, not reasoned.

The counter-example that caused the revert is **not** a hoisting or constructor
interaction at all. It is [[bug-nilpy-identifiers-are-case-insensitive]].

`a` and `A` are the SAME identifier, so `a = A()` **rebinds the class name to
the instance**. `A.n` afterwards reads the *instance's* copy of the field — which
the constructor set from the global BEFORE incrementing it — hence 0. Bare `A()`
rebinds nothing, hence 1. The variable name was the whole variable:

```python
class A:
    n = 0 + 0
    def __init__(self):
        A.n += 1
a   = A(); print(A.n)   # 0   <- `a` IS `A`
zzz = A(); print(A.n)   # 1   <- same program, different variable name
```

Decisive one-liner, no constructor involved at all:

```python
class A:
    n = 0 + 0
a = 5
print(A.n)        # prints 5 — `A` now names the integer
```

With non-colliding names the part-1 fallback is **correct in every case I
measured**: module-level read (0) and write (7), explicit write in a method (2),
augmented `Reg.k += 1` in a method (1), the counter idiom across three
constructions (3), and instance reads unaffected. The literal-initialiser case
stays a LOUD "class method not found", exactly as before — no silent wrongness
introduced there.

I also tried part 2 (make `PyClsAttrExprAhead` always true, so a literal
initialiser gets real storage too). It works: a 6-line probe covering int/str/list
class attributes, module write, the counter idiom, augmented assignment, and
`s1.v = 99` creating an instance attribute without disturbing the class one, is
byte-identical to CPython.

## So why is this still open? A DIFFERENT blocker, also measured

Both parts were reverted again, for a reason that is real:

```python
class S:
    v = 5
a1 = S(); a2 = S()
print(a1.v, a2.v, S.v)    # CPython 5 5 5     pxx 5 5 5    ok
S.v = 10
print(a1.v, a2.v, S.v)    # CPython 10 10 10  pxx 5 5 10   SILENTLY WRONG
```

Construction **copies** each class attribute into the instance field, so once a
write through the class name is possible, existing instances silently disagree
with the class. Today that is unreachable because the write is a compile error;
enabling the lookup makes it reachable. Same category as the first revert — a
loud refusal becoming a silent wrong value — via a completely different route.

Mutable class attributes are NOT affected (the instances copy the same list
HANDLE, so mutation is shared, matching CPython). It is specifically *assigning*
to the class attribute after instances exist.

## What actually has to change first

The copy-at-construction model. Python resolves `inst.attr` by looking at the
instance dict and *falling through to the class* when absent; assigning
`inst.attr` creates a per-instance override. So:

- construction should NOT copy class attributes into instance fields
- `inst.attr` should read the class global unless an instance override exists
- `inst.attr = x` should create that override — and the `pydynattr` machinery
  for per-instance dynamic attributes already exists, so this is wiring, not
  new runtime

Only once reads fall through is the `ClassName.attr` lookup safe to enable, and
at that point parts 1 and 2 are both small.

**Read-only access cannot be split out as a cheap interim**: the fallback site
(`parser.inc:4400`) returns a node the caller may use as either an rvalue or an
assignment target, so refusing only writes needs the same context plumbing.

Do NOT re-attempt parts 1/2 before the lookup model is fixed — and do not
re-diagnose the `a = A()` example, it is case-insensitivity and is settled.

> **SUPERSEDED 2026-08-03 — the first half of that sentence no longer applies.**
> The read model IS now decided (see the section at the end of this file), so
> parts 1 and 2 are exactly the work, not something to hold off on. The second
> half stands: `a = A()` is case-insensitivity, settled, do not re-diagnose it.
> Left in place rather than edited out — it was true when written, and rewriting
> the record is how the next reader loses the reasoning.

## Also found here

`from typing import ClassVar` fails to parse (`unexpected token`), so the
ClassVar-annotated route — which `PyRegisterClassMembers` explicitly supports
and registers via `FindClassVar` so that "ClassName.name resolves" — is
unreachable from NilPy source. Worth checking as part of 1, since that registry
is the other place `ClassName.attr` could resolve from.

## Gate

A `.npy` diffed against CPython covering: read/write/augmented `C.attr` at
module level and inside a method; the counter idiom incrementing across several
constructions; literal and non-literal initialisers; that instance reads still
see the class value and that assigning through an INSTANCE (`c.attr = ...`)
creates an instance attribute without disturbing the class one (Python's rule);
and a dataclass with defaults as a regression control.


## 2026-08-02 — the "Also found here" note is FIXED; the main ticket stays blocked

`from typing import ClassVar` parses fine; what failed was the **class member**
`n: ClassVar[int] = 0`. Measuring it showed the report was narrower than the bug:
EVERY annotated class attribute failed to parse — `n: int = 0`, `List[int]`,
`Dict[str, int]`, and a bare `n: int` — because the class body only matched a
name followed directly by `=`. The member pre-pass matched the same shape, so
there was no field either. Only a @dataclass accepted annotated members, through
its own branch.

Fixed in **04408c2f1**, with `test/test_nilpy_annotated_class_attribute.npy`
byte-identical to CPython.

That does NOT unblock this ticket. The ClassVar registry (`FindClassVar`, the
route through which "ClassName.name resolves") is still gated on `isDC` in
`PyRegisterClassMembers`, so a plain class's `ClassVar` now lands as an ordinary
FIELD — correct for instance reads, and it does not change the `ClassName.attr`
story at all. **The copy-at-construction blocker is untouched. Do not re-attempt
parts 1/2.**

## Related bug found in the same session — read it before the rework

[[bug-nilpy-non-literal-class-attribute-corrupts-the-class-layout]]: declaring
`g = 2 + 3` in a class makes a method returning a tuple of two OTHER class
attributes print nothing or segfault, with `g` never read. Pre-existing
(reproduced on a stashed baseline), and it lives in exactly the
`PyRegisterClassMembers` code this ticket's part 2 would have to change — the
literal and non-literal branches each call `AddUField` and advance `curOff`
independently. Plausibly the same layout disagreement seen from another side;
fixing the copy-at-construction model without understanding it risks baking the
bug in.

## 2026-08-02 — moved to blocked/, the fork is now a Track U ticket

Picked up, re-read end to end, and NOT re-attempted: the write-up's own
conclusion is that the copy-at-construction read model has to change first, and
*how* it should change is a design fork with materially different cost, not
something to settle by guessing. Filed
[[decide-nilpy-class-attribute-instance-read-model]] — full Python fall-through
with per-instance overrides (what this ticket recommends) versus a whole-program
static specialisation reusing the `PyDynAttrEverAssigned`-style module scan the
frontend already leans on. Recommendation is on that ticket.

Nothing was changed in the compiler for this ticket.


## 2026-08-03 — UNBLOCKED. The decision was "there is no decision".

[[decide-nilpy-class-attribute-instance-read-model]] is resolved: NilPy follows
CPython wherever possible, quirks included, and a known divergence is never
traded for implementation cost. So this is **one ticket, fixed once** — the real
model, not a phased approximation and not a "correct for the programs we
compile" subset.

**Implement:** reads fall through instance → class; a write through an instance
creates a per-instance override; construction copies nothing that can be reached
by fall-through. Then parts 1 and 2 above (the `ClassName.attr` lookup, and real
storage for a literal initialiser) are both small, and both were already
measured byte-identical to CPython in isolation.

The whole-program scan discussed while deciding is kept ONLY as a lowering
optimisation and must not be described as semantics: divergence from a
copy-at-construction lowering requires a class-level write AFTER construction,
so without one the cheap lowering is provably indistinguishable. Attributes
never class-written at run time keep today's copy; class-written but never
instance-written become one shared slot read directly; only the both-written
case pays for the fall-through check. The counter idiom `C.count += 1` is the
middle row — correct and free.

The framing that makes the model obvious, from the same discussion:
`self.x = ...` in `__init__` is an INSTANCE WRITE, not a field declaration —
identical machinery to `a.x = ...` from outside. One rule (reads fall through,
writes land on what you named), and ordinary per-instance fields exist only
because `__init__` performs those writes.
