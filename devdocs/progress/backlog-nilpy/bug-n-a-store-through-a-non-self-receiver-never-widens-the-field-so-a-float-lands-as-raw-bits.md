---
track: N
prio: 60
type: bug
blocked-by: []
summary: "FIXED for every store whose value the tokens can type (PyFJJoinForeignStores, between the class detect sweep and layout): `<recv>.NAME = v` through a parameter, local, module name, dotted chain, chain or tuple target now widens the field, scoped to the receiver's class when the tokens name it and name-wide across every class recording NAME otherwise. RESIDUAL, STILL SILENT WRONG VALUES: a store whose right-hand side the token pre-pass cannot type -- a call result with no inferable return, a subscript, a parameter, an attribute of an untyped receiver whose classes disagree -- joins nothing, so a float written that way into an int field still lands as its IEEE bits. Also a cost, not a defect: the name-wide fallback widens same-named fields of unrelated classes (to variant for int/float), values unchanged.""
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
