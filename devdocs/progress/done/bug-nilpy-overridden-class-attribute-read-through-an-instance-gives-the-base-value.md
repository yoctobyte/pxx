---
track: N
prio: 55
type: bug
summary: "NilPy: a class attribute overridden in a subclass reads the BASE's value through an instance — Derived().kind is 'base', while Derived.kind is correctly 'derived'. Silent wrong value on ordinary Python"
status: done
owner: claude-N
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

### Shape of the fix — MEASURED, and it is NOT the constructor split

The first guess was to key the prologue on the constructed class and run it
exactly once: split every constructor into an attribute-applying entry and a
body, point `super().__init__()` at the body, synthesise an entry for a class
that inherits its constructor. That is a large change to the constructor
protocol.

**It is not needed.** The correct model already works. Forcing the three
attributes onto the SHARED-SLOT lowering (via a class-name write, which is what
`PyClsAttrWriteScan` keys on) makes every failing row correct, with no other
change:

```python
class Base:
    kind = "base"
    def __init__(self, n): self.n = n
    def touch(self): Base.kind = Base.kind        # forces the shared-slot row

class Derived(Base):
    kind = "derived"
    def __init__(self, n): super().__init__(n)
    def touch2(self): Derived.kind = Derived.kind

class NoCtor(Base):
    kind = "noctor"
    def touch3(self): NoCtor.kind = NoCtor.kind
```

| | pxx | CPython |
| --- | --- | --- |
| `Derived(4).kind` | derived ✓ | derived |
| `NoCtor(5).kind` | noctor ✓ | noctor |
| `Base(3).kind` | base ✓ | base |

Because the shared slot is read by walking from the RECEIVER's class
(`FindClassVar`), which is the right question, while copy-at-construction asks
the constructor's. So the fix is to **stop using copy-at-construction where its
soundness proof fails and fall back to the model that already works** — which is
precisely what the 2026-08-03 decision says the scan is for (an optimization,
never semantics).

**The change:** extend the demotion condition. Today an attribute leaves the
copy lowering only when `classW` (written through the class name). It must ALSO
leave it when the attribute is **redeclared by another class in the same
inheritance chain** — the case the soundness proof forgot.

### Design 3 — SHADOW FIELDS — implemented, measured, and REJECTED 2026-08-07

Worth recording so nobody spends the day on it again. It looks like the most
surgical option and it is wrong.

The idea: `FindUField` walks the parent chain, so a redeclaring subclass never
gets its OWN field (`pyparser.inc:18703`) — give it one that shadows the base's,
and gate the hoisted-temp route on an **own** ctor rather than an inherited one
(`:4906`). Two small edits, no demotion, no constructor split, and — the
attraction — **no variant-receiver cost**, since fields stay.

It works on every row this ticket is about:

```
                     before        after        CPython
Derived(4).kind      base          derived      derived
NoCtor(5).kind       base          noctor       noctor
CtorNoSuper(6).kind  nosuper       nosuper      nosuper
super-then-read      base          superfirst   superfirst
```

**But it introduces a NEW silent wrong value**, which is disqualifying:

```python
class B:
    v = "b"
    def __init__(self): self.n = 0
    def setit(self): self.v = "set-by-base-method"
class D(B):
    v = "d"
o = D(); o.setit(); print(o.v)
```

| | result |
| --- | --- |
| CPython | `set-by-base-method` |
| **PINNED (pre-change) binary** | `set-by-base-method` ✓ |
| with shadow fields | **`d`** ✗ |

Controlled against the pinned binary, not a text revert, so the regression is
real and mine. Cause: shadowing splits ONE logical attribute into TWO storage
slots. A base method's `self.v` is statically bound to the base's field while an
external `inst.v` finds the subclass's shadowing field, so a write through one
is invisible to the other. It trades one silent wrong value for another and adds
a mechanism to a subsystem whose whole problem is having too many
(`root-cause-over-microfix.md`). Reverted; only the selector-arm fix from this
session was kept.

A related row it does NOT fix either, and which no field-based design can:
`self.attr` inside a BASE method on a DERIVED instance reads the base's value
(`Speaker`/`LoudSpeaker` probe). That needs the receiver's RUNTIME class, same
as the variant case.

### Design ranking after the elimination

1. **Shared-slot demotion (design 2) — recommended.** Correct on every static
   row, measured. Known cost below.
2. Constructor split (design 1) — larger, and does not address the variant or
   base-method rows either.
3. Shadow fields (design 3) — **rejected**, introduces a regression.

### Open risk to settle before implementing

Two things need care, and neither is hand-waveable:

1. **The whole chain must agree.** If `Derived.kind` becomes a slot while
   `Base.kind` stays a field, a `Derived` instance still *inherits* Base's
   field, `FindUField` finds it, and the class-var arm never fires. Demotion has
   to apply to every class in the chain that declares the name, not just the
   redeclaring one.
2. **Variant receivers: MEASURED, and the trade is acceptable.**
   `PyClsAttrSharedSym` resolves a slot by NAME for variant receivers and
   returns -1 when two distinct slots share a name — and a redeclared name is by
   definition two slots with one name. Measured on a heterogeneous list walked in
   a loop:

   | | `[Base(1), Derived(2)]` → `o.kind` |
   | --- | --- |
   | CPython | `base` `derived` |
   | today (copy model) | `base` `base` — **silently wrong** |
   | after demotion | `AttributeError` — **loud** |

   So demotion does not break a working row; it converts a silently wrong one
   into a loud one. The standing rule from
   [[decide-nilpy-class-attribute-instance-read-model]] is explicit — *"where
   something is not implemented yet the compilation HALTS rather than being
   silently wrong"* — so this is doctrine-aligned, not a judgement call, and
   needs no new decision. Getting the row actually RIGHT needs the receiver's
   runtime class; that is the same missing capability as
   [[bug-nilpy-list-of-custom-objects-loses-repr-str]] (a variant-boxed instance
   loses its class identity) and belongs with that family, not here.

Detection also needs the inheritance links at pre-pass time; classes are
processed in declaration order, so a base is already registered when the
subclass is seen, but the base's lowering has already been chosen by then —
either a retroactive demotion or a cheap token pre-scan in the
`PyClsAttrWriteScan` idiom (the established tool for exactly this).

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

## FIXED 2026-08-07 — shared-slot demotion (design 2), as ranked above

Implemented exactly the recommended design: an attribute leaves the
copy-at-construction lowering when it is **redeclared by another class in the
same inheritance chain**, joining the `classW` demotion that was already there.

- `pyparser.inc` — `PyClsAttrRedeclScan` builds a whole-module table of every
  class-level attribute declaration with its class and base, **from tokens**,
  because the answer depends on classes declared LATER in the module than the
  one being lowered. Same shape and same reason as `PyClsAttrWriteScan` /
  `PyDynAttrEverAssigned`; header walk and attribute predicate copied from
  `PyRegisterClassFieldsPrepass` so the two readers cannot disagree about what a
  class attribute is (the double-reader bug that already cost this family a
  segfault). `PyRdIsAncestor` / `PyClsAttrRedeclaredInChain` answer the chain
  question in **either direction** — open risk (1) above: the base must demote
  too, or a subclass instance still inherits the base's field via `FindUField`
  and the class-var arm never fires. Overflow answers True (demote), so the
  failure mode costs the optimization, never correctness.
- `parser.inc:7689` — the selector path gets the per-instance-override
  fall-through ahead of the plain class-var arm, mirroring the `ParseFactor`
  site's existing precedence. Without it a demoted attribute read through a
  non-bare receiver would ignore an override a constructor had just created.
- `defs.inc` — the tables.

### Measured, controlled against the PINNED (pre-change) binary

| row | pinned | fixed | CPython |
| --- | --- | --- | --- |
| `Derived(4).kind` (super in ctor) | **base** | derived ✓ | derived |
| `NoCtor(5).kind` (inherited ctor) | **base** | noctor ✓ | noctor |
| `CtorNoSuper(6).kind` | nosuper ✓ | nosuper ✓ | nosuper |
| `Plain(7).kind` (no redeclaration) | base ✓ | base ✓ | base |
| `self.kind` after `super().__init__()` | **base** | derived ✓ | derived |
| instance override on top | ✓ | ✓ | ✓ |
| base method's `self.v` seen externally | ✓ | **✓** | set-by-base-method |

That last row is the one that disqualified design 3 (shadow fields); demotion
keeps it correct, because it never splits the attribute into two slots.

### The two rows deliberately NOT fixed — both need the RUNTIME class

1. `self.attr` inside a **base** method on a derived instance still reads the
   base's value (unchanged from pinned, so not a regression).
2. A heterogeneous list walked in a loop is now a **loud** runtime
   `AttributeError: 'Base' object has no attribute 'kind'` where it used to
   print `base base` **silently wrong**. Exactly the trade measured in "Open
   risk" (2), and doctrine-aligned per
   [[decide-nilpy-class-attribute-instance-read-model]].

Both are the same missing capability — a variant-boxed instance loses its class
identity — and belong with [[bug-nilpy-list-of-custom-objects-loses-repr-str]].

### Test

`test/test_nilpy_overridden_class_attribute.npy` (+ `.expected`, registered in
the Makefile's nilpy block): 11 lines **byte-identical to the CPython oracle** —
instance and class-name spellings, a non-redeclaring subclass, an attribute the
subclass does not redeclare, the read inside the derived ctor after `super()`,
a per-instance override on top, and the base-method-write row as a standing
guard against the shadow-field design being retried.

**Gate:** self-host fixedpoint + `tools/gate.sh quick`.

## Log
- 2026-08-07 — resolved, commit e3827d30b.
