---
track: N
prio: 40
type: bug
summary: "class D(B, C): does not parse — a second base is an 'unexpected token' at the comma, so multiple inheritance and every mixin idiom is unavailable"
status: done
owner: agent-AN
---

# `class D(B, C):` does not parse

- **Type:** bug / missing language feature (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping previously-unswept surfaces vs CPython.
- **Loud**: a parse error, not a silent wrong answer.

```python
class A:
    def who(self):
        return "A"

class B(A):
    def who(self):
        return "B"

class C(A):
    def who(self):
        return "C"

class D(B, C):     # <-- error: unexpected token, at the ','
    pass

print(D().who())   # CPython: B  (MRO: D, B, C, A)
```
```
pascal26:22: error: unexpected token
  near:    D  B >>>  C
```

Single inheritance works. Only the comma is rejected, so the class header
parser evidently takes exactly one base.

## Why this is prio 40 and not higher

It fails loudly at compile time, and single inheritance covers the overwhelming
majority of real NilPy code. But it blocks every **mixin** idiom, which is how
a lot of ordinary Python is structured, so it will keep being hit by corpus work.

## The real cost is the MRO, not the parse

Accepting the comma is the easy half and is NOT the feature. Python resolves
attributes by C3 linearisation, so `D().who()` must give `"B"` — and with a
diamond (both B and C deriving from A) the order is D, B, C, A, which is
observable whenever two bases define the same name. The underlying Pascal
object model is single-inheritance, so a second base cannot be a real parent.

Options, roughly in order of honesty:

1. **Full C3 with explicit dispatch** — flatten the linearisation at compile
   time and resolve each attribute to the winning definition. Correct, and the
   most work.
2. **Second base as a delegate** — real inheritance from the first base, and
   attributes not found there forwarded to an embedded instance of the second.
   Handles mixins, gets the diamond wrong in the case where C3 would pick C
   over an inherited-from-A member of B.
3. **Refuse a second base explicitly** — replace "unexpected token" with a
   diagnostic naming multiple inheritance. Cheap, honest, and strictly better
   than today's error, which reads like a parser bug.

Option 3 is worth doing immediately regardless of which of 1/2 is chosen later.
Do NOT accept the comma and silently ignore the second base: that turns a
compile error into a wrong method being called at run time.

## Gate

A `.npy` diffed against CPython covering: a plain mixin (bases with disjoint
methods), a diamond where the MRO is observable, and `isinstance` against both
bases.


## 2026-08-04 — option 3 landed; the FEATURE is still open

Did the part this ticket said was "worth doing immediately regardless of which
of 1/2 is chosen later", and deliberately nothing more.

`class D(B, C):` now says what is actually wrong:

```
Nil Python: multiple inheritance is not supported — `class D` names more than
one base. Python resolves these by C3 linearisation and the object model here is
single-inheritance, so a second base cannot be honoured; it is refused rather
than silently ignored. Use single inheritance, or compose: hold the would-be
second base as a field and forward to it
```

instead of `unexpected token` pointing at the comma, which read like a parser
bug rather than a missing feature — and left the reader with no idea whether to
work around it or file it.

The message states the constraint (single-inheritance object model), why the
comma cannot simply be accepted (C3 is observable the moment two bases define
the same name), and the workaround, so it is actionable without reading this
ticket.

**Deliberately NOT done:** accepting the comma. The ticket is explicit and it is
right — taking a second base and dropping it converts a compile error into the
WRONG METHOD being called at run time, which is worse than not supporting the
feature.

Single inheritance, `class E(Exception)`, and dotted bases are unchanged
(verified against CPython). `tools/gate.sh quick` GREEN, self-host
byte-identical.

**Ticket stays OPEN** for option 1 (full C3 with explicit dispatch) or option 2
(second base as a delegate). Nothing about that choice is foreclosed by this;
the diagnostic is what a reader hits either way until one of them lands.

## 2026-08-08 — RE-SCOPED by decision: FLATTEN. The option list above is superseded

[[decide-nilpy-multiple-inheritance-c3-or-delegate]] is decided and the answer
is **none of the three options this ticket lists**. Do not implement 1, 2 or 3
from the section above; they are kept only as the record of how the question was
framed.

**Build this instead — v1:**

1. **Flatten.** Accept the comma; copy each extra base's methods into the
   derived class, compiled with `self` = the DERIVED class, conflicts resolved
   in **C3 left-to-right** order (first base wins). Class-level attributes on the
   flattened base come along too — and that touches the class-attribute lowering
   reworked 2026-08-07 (shared slot vs copy-at-construction), so verify that
   interaction rather than assuming it.
2. **Refuse the diamond.** Two bases sharing an ancestor: C3 gives ONE shared
   ancestor, naive flattening can give two, and the state then diverges. Compile
   error naming it, in the spirit of the diagnostic that already landed here.
3. **Diagnose `super()` across a flattened base.** CPython routes
   `super().__init__()` in the first base to the SECOND base via the MRO; a
   flattened body goes to its own base instead. Silence here would be a wrong
   call at run time, so it must be a compile-time error or warning.

**Explicitly NOT in v1:** `isinstance(d, C)` will answer False where CPython says
True. That is the known cost, it is loud rather than silent, and it is fixed
later by synthesising an interface per flattened base — which rides the RTTI
interface table and IMT that already exist (`PXX_RTTI_PARENT` is a single parent
pointer, but every implemented interface already gets a 24-byte RTTI entry).

**Why not delegate** — the option this ticket previously recommended: a mixin's
`self` IS the derived object in Python, so an embedded instance cannot see the
host's attributes and the common mixin breaks. Full reasoning in the decision.

### Gate (unchanged in spirit, sharpened)

A `.npy` diffed against CPython covering: a plain mixin (disjoint methods), a
mixin whose method reads an attribute of the DERIVED class (the case delegation
would fail), left-to-right conflict resolution where both bases define the same
method, class attributes carried from a flattened base — plus `{%FAIL}`-style
checks that the diamond and a `super()` chain across a flattened base are
refused with their own messages.

## Resolution (2026-08-15) — v1 FLATTEN, as decided

`class D(B, C):` compiles. Built exactly as the 2026-08-08 re-scope specifies.

**Nothing is copied.** A class's body token span is recorded (`PyClsBodyS/E`)
and a flattened base's span is *replayed* with `ci` = the derived class, in both
passes: the member registration walks the own body then each base's span, and
the body parse rewinds the cursor into each base's span after its own dedent.
So a mixin's methods compile with `self` = the derived object, which is what
Python means by a mixin — and the derived class's fields are in scope, which is
precisely the case a delegate object cannot serve.

The pieces:

- **Conflict order is C3 left-to-right.** `PyMixBuildSkip` builds the losing set
  before each base's span is replayed: the derived class's own definitions, then
  everything the real parent chain supplies, then everything an earlier base
  supplied. Both passes call the same builder and the same `PyDefMemberKeyAt`,
  because a disagreement compiles a proc for a member that was never registered.
  The parent-chain half was not obvious and was measured, not reasoned: without
  it a flattened base's `who` was registered as an *override* of the parent's
  slot and silently WON, where CPython gives the parent's.
- **A flattened class is flattened everywhere.** A class named as a second base
  anywhere in the program is marked `PyClsUsedAsMixin` by a pre-scan, and is
  then flattened even in *first* position, and its body is never compiled
  standalone. This is forced: the canonical mixin reads members it does not
  declare (`self.name`, `self.hello()`), which resolves only against a host.
  `class E(M1, M2)` was the case that proved it — with M1 left as a real parent
  it inherited a class whose method bodies had never been compiled.
- **The diamond is refused**, naming the shared ancestor: C3 gives it one copy,
  flattening gives two, and the two copies' state then diverges silently.
- **`super()` in a flattened body is refused**, naming the base: CPython routes
  it along the derived class's MRO, and a flattened body can only reach the
  derived class's own single parent. Verified against CPython, which raises
  `AttributeError: 'super' object has no attribute 'go'` for the same program —
  i.e. the answer we would have given was wrong, not merely different.

`isinstance(d, C)` against a flattened base answers False. That is the v1 cost
the re-scope names, it is loud, and it is fixed later by synthesising an
interface per flattened base. All three divergences are written up in
`devdocs/dev/nilpy-semantics-divergences.md`.

**Gate:** `test/test_nilpy_multiple_inheritance.npy` (+`.expected`, wired into
the Makefile) covers a three-base class, a mixin method reading a derived-class
attribute, parent-wins and derived-wins conflict resolution, left-to-right
between two mixins, and class attributes carried from a flattened base — all
byte-identical to CPython. The two refusals were checked by hand against the
CPython programs they refuse. `tools/gate.sh quick` GREEN, self-host
byte-identical, and the four class/attribute-layout nilpy tests re-diffed
unchanged.

## Log
- 2026-08-15 — resolved, commit b9e8a9b3c.
