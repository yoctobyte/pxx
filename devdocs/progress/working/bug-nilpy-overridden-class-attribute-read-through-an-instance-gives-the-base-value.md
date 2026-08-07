---
track: N
prio: 55
type: bug
summary: "NilPy: a class attribute overridden in a subclass reads the BASE's value through an instance — Derived().kind is 'base', while Derived.kind is correctly 'derived'. Silent wrong value on ordinary Python"
status: working
owner: claude-AN
---

# An overridden class attribute reads the base's value through an instance

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-07, by a probe that could not compile until
  [[bug-nilpy-unbound-base-class-init-call-is-rejected]] was fixed earlier the
  same day. **Pre-existing, not a regression** — controlled by running the same
  repro on the PINNED binary, which predates every change in that session and
  gives the identical wrong answer.

## Measured

```python
class Base:
    kind = "base"
    def __init__(self, n):
        self.n = n

class Derived(Base):
    kind = "derived"
    def __init__(self, n):
        super().__init__(n)

print(Base(3).kind, Derived(4).kind)   # CPython: base derived   pxx: base base
print(Base.kind, Derived.kind)         # CPython: base derived   pxx: base derived
```

So the value is reachable and correct **through the class name**, and wrong
**through an instance**. The receiver's own class is not consulted; the read
resolves to the base's slot.

## Why the existing ticket does not cover it

[[bug-nilpy-class-attribute-unreachable-through-the-class-name]] (done) built
the shared-slot + per-instance-override model and its test covers *"inheritance
through the subclass NAME"* — the row that works. An instance read of an
attribute the subclass **re-declares** is the untested neighbour, and it is the
spelling ordinary code uses (`self.kind` inside a method is the same shape).

## ROOT CAUSE — measured 2026-08-07 at `9e9509e96` (gate.sh quick GREEN, borg)

**The fork below rests on a wrong model and is superseded.** The read is not at
fault: it resolves correctly. The *write* at construction is. Both
`PyClsAttrEnsureGlobal` (own-class registration) and `PyFindClsAttr` /
`PyClassAttrInitSeq` (ancestor chain, ROOT FIRST so a redeclaring subclass
stores last) are already correct. The defect is one level up.

`pyparser.inc:4901-4906`: a class *with* a constructor applies its class
attributes at the **head of that constructor** (`PyClassAttrInitSeq`), and a
class *without* one uses the hoisted-temp form. That prologue is keyed on the
**constructor's own class** — but a construction may run more than one
constructor, and the one that runs is not necessarily the constructed class's.
Two failures fall out, and they are the same defect:

```python
class Base:
    kind = "base"
    def __init__(self, n): self.n = n

class Derived(Base):          # own __init__ that calls super()
    kind = "derived"
    def __init__(self, n): super().__init__(n)

class NoCtor(Base):           # redeclares, NO own __init__
    kind = "noctor"

class CtorNoSuper(Base):      # own __init__, no super() call
    kind = "nosuper"
    def __init__(self, n): self.n = n
```

| case | pxx | CPython |
| --- | --- | --- |
| `Derived(4).kind` | **base** | derived |
| `NoCtor(5).kind` | **base** | noctor |
| `CtorNoSuper(6).kind` | nosuper ✓ | nosuper |

1. **`super().__init__()` re-runs the base's prologue**, overwriting the derived
   values the derived prologue just wrote. Measured directly: a `self.kind` read
   *inside* the derived constructor immediately after `super().__init__(n)`
   already answers `base`. An explicit `self.kind = "explicit"` after the super
   call does survive, which locates the clobber precisely at the super call and
   not in the read.
2. **A subclass with no own constructor** runs only the base's, whose prologue is
   keyed on the base — so its redeclared attributes are never stored at all.
   `FindUMeth(ci, 'create')` at :4906 finds the *inherited* ctor, so the
   hoisted-temp fallback is suppressed too, and nothing applies them.

`CtorNoSuper` is right only by accident: one prologue runs, for the right class.

This also explains why the existing test `test_nilpy_inherited_class_attribute`
is green on `Deep().n == 42` — a redeclared attribute read through an instance,
the very row this ticket calls broken. There `Base` has **no `__init__` at
all**, so every class takes the hoisted-temp route and the per-constructor
prologue never enters the picture. The untested combination is *redeclared
attribute + a constructor in the chain*.

### A SECOND, separate defect found by the same sweep — FIXED 2026-08-07

An instance read of a class-WRITTEN (shared-slot) attribute was refused **when
the receiver was not a bare identifier**:

```python
class Counter:
    made = 0
    def __init__(self, n):
        Counter.made += 1     # class write -> 'made' takes the shared-slot row
b = Counter(1)
print(b.made)                 # 1 — always worked
print(Counter(1).made)        # was: error "made": no such member on this record/class
```

Same object, same attribute, two spellings, one refused. Narrowed by bisecting
the receiver shape: the bare-identifier path in `ParseFactor` has a "class
variable accessed via an instance" fall-through (`parser.inc:6378`), and
`ParseClassRecordSelectors` — the route a call result, index, or chained field
takes — had no such arm, so it fell to `RequireRecMember` and errored. A
class-written attribute has no instance field *by construction*, so that arm is
not optional.

**Fixed** by giving the selector path the same fall-through, mirroring the
existing arm rather than adding a second mechanism. Test:
`test/test_nilpy_class_attr_shared_slot_via_call_result.npy`, byte-identical to
the CPython oracle across six receiver shapes (bare ident, call result, shared
slot across instances, ordinary field via call result, index, chained field,
class name).

Loud rather than silent, so this was the cheap half. The clobber above is the
expensive half and is still open.

### The real shape: a matrix with holes

A class attribute has **three lowerings** (copy-at-construction field; shared
global slot; slot + per-instance override — chosen per attribute by
`PyClsAttrWriteScan`, pyparser.inc:3822) and **four access routes** (`C.attr`,
bare `attr` in a method, `inst.attr` statically typed, `inst.attr` on a variant).
The matrix is not filled in. Four bugs in `done/` and both defects above are each
one empty cell, and each arrived as its own "small" bug with its own plausible
cause. That is the design flaw; the individual cells are symptoms.

The macro answer is already DECIDED and needs no new fork:
[[decide-nilpy-class-attribute-instance-read-model]] (2026-08-03) chose full
CPython fall-through, *"not phased, not approximated"*, with the scan surviving
**as an optimization only, never as semantics**. This ticket is therefore
authorised to fill the matrix rather than patch a cell. See
`devdocs/dev/root-cause-over-microfix.md`, for which this is the worked example.

### Shape of the fix

The prologue must be keyed on the **constructed** class and run **exactly
once**, before any user `__init__` body. That means splitting each constructor
into its attribute-applying entry and its body, and making `super().__init__()`
target the **body**, not the entry — plus giving a class that inherits its
constructor an entry of its own. It is a lowering change, not a lookup change.

`--- superseded below ---`

## The fork worth settling before implementing

A class attribute is a class-level GLOBAL, so an instance read compiles to a
global address. Two levels of fix, and they are not the same size:

1. **Static receiver class.** In the repro the receiver's static type IS
   `Derived`, so resolving the class-var by walking from the *receiver's* class
   rather than the declaring base would fix it — and `self.kind` inside a method
   too. Small, and covers the common case.
2. **Runtime receiver class.** A `Base`-typed variable holding a `Derived`, or a
   heterogeneous list walked in a loop, needs the read dispatched on the
   RUNTIME class. That is a different mechanism from a global address.

Doing (1) alone leaves (2) silently wrong, which is exactly the
`devdocs/dev/normalise-dont-special-case.md` trap — a second path that stays
broken. Worth deciding deliberately rather than taking (1) because it is
reachable: either land (1) *with* (2) filed and linked, or make (2)'s shape
diagnose rather than answer wrongly.

## Gate

Per-fix loop. A `.npy` test covering: the overridden attribute through an
instance and through the class name, `self.attr` read inside a base method on a
derived instance, a Base-typed binding holding a Derived, a heterogeneous list
walked in a loop, an attribute the subclass does NOT override (must still find
the base's), and a per-instance override on top — diffed against CPython with
`tools/pydiff.py`.
