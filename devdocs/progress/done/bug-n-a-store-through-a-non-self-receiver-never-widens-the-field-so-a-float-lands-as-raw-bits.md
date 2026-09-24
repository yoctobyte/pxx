---
track: N
prio: 80
type: bug
blocked-by: []
summary: 'FIXED. MECHANISM: a field stored through a receiver other than `self` was never joined, so a float landed in an int slot as its bits. PyFJJoinForeignStores (between the class detect sweep and layout) now joins every `<recv>.NAME = v`: a typable v widens the field by PyWidenBinding; a bare parameter is typed by its annotation or its call sites; a v the tokens cannot type widens any SCALAR or CLASS field it can reach to variant, so the value is stored as CPython stores it. Scoped to the receiver class when the tokens name it, name-wide otherwise. The one place pxx differs from CPython: a non-instance stored into an ANNOTATED class-typed local (`n: N = y`) raises TypeError (pyvarobj_store), because there the programmer declared the type; CPython would store it."'
status: done
---

# A store through a non-self receiver never widens the field

Found 2026-09-24 (frankb-12) while working the parameter-receiver unpack ticket,
whose own store was already fixed: the variations put a DIFFERENT TYPE through
the same receivers and every one of them came back wrong, including the plain
single statement, so this is not an unpack defect.

## Measured at HEAD, x86-64, against CPython 3 on the same file

```python
class A:
    def __init__(self):
        self.s = 0
        self.f = 0.5

def var_into_int(b):   y = 1.5; b.s = y;  print(b.s)   # CPython 1.5  pxx 4609434218613702656
def field_into_int(b): b.s = b.f;         print(b.s)   # CPython 0.5  pxx 4602678819172646912
def int_into_float(b): b.f = 3;           print(b.f)   # CPython 3    pxx 3.0
def local_recv():      a = A(); y = 2.5; a.s = y; print(a.s)   # CPython 2.5  pxx 4612811918334230528
def literal(b):        b.s = 1.5;         print(b.s)   # CPython 1.5  pxx 1   (truncated)
```

The same through a tuple target (`b.s, x = 1.5, 2`) and a chain target
(`b.s = b.u = 33`) behaves identically: they reach the field through
`PyMakeAttrStore`, which assigns the value node straight into the `AN_FIELD`.

## Why it is the field join and not the store

The `self` case was fixed in
[[bug-n-a-fields-type-is-fixed-by-its-first-assignment-and-never-widened]]: the
class pre-pass now joins every `self.<f> = <expr>` with PyWidenBinding, the same
join locals use. It is token-driven and runs BEFORE any body is typed, so it can
recognise `self` and nothing else -- `b.s = ...` names a receiver whose class is
not known until the def is parsed. By then the layout is fixed.

## What a fix has to do, and what it must not

- **Not** a coercion at the store. Converting float-into-int would make the
  bits case agree with the literal case, and both are wrong: in Python the
  field BECOMES a float.
- **Not** a refusal either, as a first move: it would turn working programs
  whose bad path never runs into programs that do not compile. Worth having
  only as the fallback for a receiver whose class cannot be determined.
- The shape of a real fix: let the typing rounds note "field f of class C
  receives type T" at every static-field store (the trial parse already
  iterates to a fixpoint for locals via PyTypingChanged), and re-lay-out the
  class when that widens a field. A field widened to variant is what
  PyWidenBinding already answers for the int/float rebind.

Would retire this: the five rows above printing CPython's answers.

## Design (2026-09-24, frankb-12) -- no re-layout needed

The re-layout above is not required. The class pre-pass already runs in two
phases over EVERY class: phase 0 (PyCollectClassFieldJoins) only DETECTS, filling
the (class, field) -> joined-type table PyFJ*, and phase 1 lays out from that
table. Nothing is laid out until phase 0 has seen the whole program. So a
non-self store can be joined in the same place, before any layout exists:

1. After phase 0's class walk, one token scan of the whole module for
   `<ident> . NAME = <rhs>` at a statement start, `<ident>` not `self`
   (the self stores are the class walk's). Tuple/chain targets later.
2. Type `<rhs>` token-wise, the way the shell pre-pass must (PyLocals do not
   exist yet): PyInferExprType; a bare ident is chased with PyRetNameType over
   the enclosing def's body; `<ident>.F` answers PyFJTk of F when every class
   recording F agrees.
3. Join the answer with PyFJNote into EVERY class whose table already records
   NAME. The receiver's class is unknown at token level; joining into all
   same-named fields is conservative (widening is always correct, costs speed
   only where names collide).
4. An UNKNOWN rhs joins nothing, so an untypable rhs is still the old bug. That
   is deliberate: widening on unknown would turn every `node.next = other` field
   into a variant. Residual, recorded rather than guessed.

## RESOLVED (2026-09-24, frankb-12) -- the typable half

Built as designed above. Fixture
`test/test_nilpy_a_store_through_a_non_self_receiver_widens_the_field.npy`
(eleven rows, CPython's output as `.expected`) covers the five rows above, a
chain, an annotated-parameter tuple target, a str into an int field, and the
BYSTANDER classes C (declared before) and D (after) holding a same-named int
field. The bystanders are reached by the name-wide join (their field becomes a
variant) and print `==`, `//`, `%d`, `str()` and `+` exactly as CPython does.
Pin v421 (binary sha256 4e32f1dde0ec) gets 8 of the 11 rows wrong. The
bystander rows are identical under both compilers.
`PXXDBG=n.fjforeign` prints, per store, which join it took: scoped (with the
class id), name-wide, or skipped.

## RESOLVED, the untypable half (2026-09-24, frankb-12)

The coordinator refused p60 for a silent residual, rightly. Measured before
choosing: census of non-self stores via `PXXDBG=n.fjforeign`. Population:
every .npy directly under test (1065), examples .py/.npy (16), and
lekkerzeilen at 9db2e38 (every lekkerzeilen .py compiled as a subject, so
rows from imported modules repeat). Compiler: the first landing. Untypable-rhs
rows: 45 in test, 9 in lekkerzeilen (6 distinct). Only those reaching a SCALAR
field can go wrong: 13 rows in test, 3 distinct in lekkerzeilen (`gain`,
`level`, `left`).
The residual was worse than raw bits: the setter shape `def f(b, y): b.s = y`
TRUNCATED a float into an int field (2 for 2.5), and an int into a str field
SEGFAULTED.

Fix: a bare parameter is now typed the way the body pass types it (its
annotation, else PyParamTypeFromSites), which cleared `level`. Anything still
untypable widens a scalar field to variant. After: two lekkerzeilen fields are
widened, `gain` (audio.py:270) and `left` (ui.py:986). The fixture gained the
setter rows. Pin v421 (4e32f1dde0ec) gets 9 lines of it wrong.

## RESOLVED, the class-field case (2026-09-24, frankb-12)

`def put(h, y): h.node = y` with y = 5 segfaulted: every store of a variant
into a class-instance slot unboxed with plain `pyvarobj`, which returns the
payload unchecked. The three store sites (field through a variant receiver,
field through a typed receiver, annotated local) now use `pyvarobj_store`,
which raises TypeError for a non-object tag, passes None as nil, and does not
retain (the store retains, as PyStoreRhsToClassSlot records). Plain `pyvarobj`
is untouched, because its dispatch callers need a non-object to fail an `is`
test, not raise. Fixture
`test/test_nilpy_a_non_instance_stored_into_a_class_slot.npy`; its
`.expected` is pxx's own output, since CPython would store the value. Pin v421
(4e32f1dde0ec) prints `stored` on all nine raising rows.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6aa68e085b.

## Amended (2026-09-24, frankb-12, at the coordinator's call)

6aa68e085b raised TypeError at all three class-slot store sites. For an
INFERRED field that goes the wrong way: `h.node = 5` is working CPython, and
NilPy may only diverge by accepting more, never by refusing more
(devdocs/dev/nilpy-semantics-divergences.md). So an untypable store now widens
an inferred class field to variant, as it already did for scalar fields, and
reads back 5. pyvarobj_store stays at the store sites and now fires only where
the slot is still class-typed: the annotated local, and a field whose every
store the tokens could type. Renamed fixture:
`test/test_nilpy_a_non_instance_stored_into_a_class_slot.npy`; it matches
CPython except the three annotated-local rows.
