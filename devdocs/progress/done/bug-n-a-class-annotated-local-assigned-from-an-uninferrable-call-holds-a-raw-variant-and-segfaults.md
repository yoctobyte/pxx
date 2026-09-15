---
track: N
prio: 90
type: bug
blocked-by: []
summary: "`v: Vec3 = s.mk()` where `mk`'s return type cannot be inferred stores a raw variant into a class-typed slot: a field read returns a denormal (the pointer reinterpreted) and a method call SEGFAULTS. Unannotated is correct, so ADDING the annotation is what breaks it."
status: done
---

# A class-annotated local assigned from an uninferrable call holds a raw variant and segfaults

```python
class Vec3:
    def __init__(self, x: float, y: float, z: float):
        self.x = x; self.y = y; self.z = z
    def norm1(self):
        return self.x + self.y + self.z

class State:
    def __init__(self):
        self.position = Vec3(1.0, 2.0, 3.0)
    def mk(self):
        return self.position          # return type NOT inferrable

s = State()
v: Vec3 = s.mk()
print("field read:", v.x)             # 6.8526596474162e-310   CPython: 1.0
print("method call:", v.norm1())      # SEGFAULT, core dumped  CPython: 6.0
```

`PXXDBG=n.locals` reports `v tk=6 rec=0` — the slot is declared a `Vec3`. The
value arriving is a variant and nothing unboxes it, so the class-typed slot holds
a raw variant payload. The denormal is the POINTER REINTERPRETED AS A DOUBLE; the
method call dereferences garbage.

**Both failure modes are bad and the quiet one is worse.** A field read returns a
plausible-looking float with no diagnostic; only a method call crashes. A program
that merely reads fields off such a local produces wrong numbers forever.

## The condition is an AND, pinned by matrix

| callee's return | local | result |
| --- | --- | --- |
| `return self.position` | `v: Vec3` | **WRONG / segfault** |
| `return self.position` | `v` (unannotated) | OK |
| `return self.position`, callee `-> "Vec3"` | `v: Vec3` | OK (**but see below**) |
| `return Vec3(...)` (inferrable) | `v: Vec3` | OK |
| plain function, same shape | `v: Vec3` | **WRONG** |
| `d: float = s.mk().x` | annotated float | OK |

**An annotated local breaks if and only if the call it is assigned from has a
return type the compiler cannot infer.**

**THE "ANNOTATE THE CALLEE RESCUES IT" ROW IS REFUTED ON REAL CODE AND MUST NOT
BE QUOTED AS A WORKAROUND.** It is true in six measured shapes — one hop, two
hops over an unannotated inner, two hops over an annotated inner, an unannotated
RECEIVER with an annotated callee, a forward-referenced `-> 'Vec3'`, and a plain
function. It is FALSE on lekkerzeilen's `sim.py`: with 23 call-site annotations
plus 14 return annotations on `State`, `Quat` and `Vec3`, the build segfaults
byte-identically to the one with no return annotations at all (rc=139, same tick,
same marker, twice). The hop that defeats the rescue is **unidentified** — I
could not construct it, and the seat that has the failing tree could not isolate
it either.

Recorded this way deliberately: the matrix is a real measurement of the shapes it
covers and a false rule about the population that matters.

**TRIGGER CONFIRMED BY THE CONTROL THAT MATTERS.** Same compiler, same tree, the
SAME 14 return annotations as the build that segfaulted, with the 23 annotated
locals removed: it runs clean for 180s (rc=124, the timeout, 332 frames). So the
defect attaches to the ANNOTATED LOCAL and to nothing else, and a return
annotation neither causes nor rescues it. That is a positive and a negative arm
differing in exactly one thing, which is what the six-shape matrix could not
supply.

**AND THE FIX MUST NOT BE SCOPED TO THE MATRIX.** Two consequences: it has to
cover the case where the callee IS annotated, because that one is broken today on
real code; and it should not be validated against these rows alone, since they
certify a rescue that does not hold. The store fix is independent of all of this
— it makes a variant landing in a class slot correct whatever the reason it is a
variant — which is the argument for fixing the STORE rather than chasing the
inference. Annotate both ends or neither; the
reading end alone is the broken combination. Not loop-specific (in-loop and
straight-line spellings fail identically), not method-specific, not class-
specific. The annotated-`float` row is the tell for the mechanism: a
variant-to-double COERCION exists, a variant-to-class-pointer one does not, so
the class case stores raw where the scalar case converts.

## Why it is 90

The edit that triggers it — adding a type annotation — is exactly what a user
does to make code faster, and it is what our own performance guidance tells them
to do. There is no diagnostic. The two annotations most likely to be written
together (`x: Vec3` at the call site, nothing at the definition) are the broken
pair, while the SAFE spellings are "no annotation at all" and "annotate the
definition" — so the naive optimisation attempt lands squarely on the defect.

## Provenance and the shape it was NOT

Found 2026-09-15 from the lekkerzeilen seat's report that adding 23 local
annotations to `sim.py` turned a working 2.18 fps build into a deterministic
segfault on the first physics tick, between their `contrib-in` and `contrib-out`
markers. Their candidate was **an annotated assignment inside a loop body** —
the only structural feature distinguishing the five annotations they suspected.
It is not the loop: the same annotation outside any loop fails identically. Had
the loop hypothesis been tested by reverting those five, it would have appeared
to work, because those five are also the ones assigned from `to_world` — the
right rows for the wrong reason, which would have left the rule wrong in the
notes and the other eighteen a hazard.

Their `to_world` is `return self.orientation.rotate(body_offset)`, a method
returning a method's result — measured separately as not inferring
(`bug-n-annotating-a-local-that-is-returned-destroys-the-defs-inferred-return-type`,
the `r_selfcall` row). That ticket and this one are siblings: there the missing
inference costs SPEED, here the same missing inference costs CORRECTNESS once an
annotation disagrees with it.

## The fix, and the cheaper half of it

Proper fix: a variant-to-class-pointer store must unbox (or refuse). The scalar
path already converts, so the asymmetry is the bug.

**A diagnostic alone would retire the worst of this** even before the store is
fixed: the compiler KNOWS the declared kind is `tyClass` and KNOWS the expression
is `tyVariant`, which is precisely the pair it currently stores raw. Refusing
that pair would turn a segfault-or-denormal into a compile error naming the two
types — and per CLAUDE.md, leaving the mistake visible beats guessing. Users
reach for the annotation to go faster; today it takes their program apart.

## The fix, located

`PyUnboxVariantToClassEx(node, ci, owned)` already exists in `pyparser.inc` — it
wraps the value in `pyvarobj` and casts to the class — and is already applied to
call ARGUMENTS landing in a class-typed dataclass field. It is simply not applied
on the assignment path.

The store goes through `PyCoerceAssignmentRHS(lhsTk, rhsNode)`, called from
exactly three places, all assignment spellings. Today it does ONE thing: rewrite
an integer literal to a double when the slot is a double. **That is why the
annotated-`float` row works and the class row does not — the scalar case got a
coercion and the class case never did.** It is a `procedure` that mutates in
place and so cannot REPLACE a node, which is likely why the class arm was never
added: the unbox returns a NEW node and the signature had nowhere to put it.

So: make it a function, pass the target's `RecName` beside its kind, and when the
slot is a user class and the RHS is `tyVariant`, return the unbox. Three callers,
one helper, no new path — fixing one caller instead would be the same one-arm
mistake this repo has hit four times in two days.

**`owned := True`, and this is the part to get right.** The dataclass site's own
comment records why: an unboxed pointer is a bare reference, while the variant
TEMP it came from is released at the end of the statement and takes the object
with it — so without the retain the slot points at a freed block, correct at the
assignment and garbage at the first read. That is a strictly nastier bug than the
one being fixed.

## User-facing rule, and it survives the fix

From the lekkerzeilen seat, in their words: **"annotate the definitions, never
only the call sites."**

**Read the second half as "and NOT the call sites", not as "as well as".** A
build with the definitions annotated AND the call sites still annotated
segfaults exactly as before — measured, twice — so annotating the definitions
does not make a call-site annotation safe. The rule earns its place on the speed
result and on the defect's shape (no annotated local means nothing for it to
attach to), NOT on a measured rescue, because there is no measured rescue. It is
the
high-leverage route for speed because one annotation at a definition types every
caller (measured: four return annotations moved thirteen hot locals where three
constructor annotations moved none, and definitions-only took 41 -> 30 with no
annotated local anywhere). Worth saying in the NilPy docs regardless of this bug,
because the failure it prevents is silent.

## FIXED — and what the fix does NOT check

Implemented as `PyStoreRhsToClassSlot(symIdx, rhsNode)` in `pyparser.inc`, a
separate helper rather than a fourth arm inside `PyCoerceAssignmentRHS`. The
plan above said to make that procedure a function and thread the target's
`RecName` through it; that was wrong in one respect and the ticket should say
so. It is shared by THREE sites and one of them is the AUGMENTED assignment,
where the node becomes an OPERAND of an `AN_BINOP` rather than the stored value
— coercing it to the target's class there would be wrong for `v += 1`. Widening
an int literal IS right at all three; the unbox is right at two. That asymmetry
is the reason for a separate helper, and folding it in would have shipped a
fourth-site bug in the same week this repo shipped a third-site one.

Verified: `field read: 1.0`, `method call: 6.0`, matching CPython exactly, where
the same program gave `6.85e-310` and a core dump. All five matrix rows pass.
Fixture `test/test_nilpy_a_class_annotated_local_from_an_uninferrable_call_is_unboxed.npy`,
wired into the Makefile, twenty rows including nine `_ok` rows that a fix
unboxing indiscriminately would redden. **Its positive control is the pinned
compiler, which fails it with `rc=139` and `field_bad FAIL got
6.2639678662742e-310`** — drawn from the population the question is about, and
the failure is the original defect rather than a manufactured one.

**THE GAP, AND IT IS IN THE FIX RATHER THAN IN THE BUG: `pyvarobj_owned` IS
RETAIN-BUT-UNCHECKED.**

```pascal
function pyvarobj_owned(const v: Variant): Pointer;
begin
  Result := Pointer(PPyVarRec(@v)^.Payload);
  if PyVarSlotIsObj(PPyVarRec(@v)^.VType) then PXXObjRetain(Result);
end;
```

It hands back the payload bits whatever the tag says, and retains only when the
tag is an object. So a class-annotated local assigned from a call that at
RUNTIME yields a double, a str or a container now has those bits reinterpreted
as an instance pointer, with no retain and no diagnostic. pylib's own
`pyvarobj_arg` comment records that exact failure from the argument-binding
site: *"a variant holding a STRING was reinterpreted as an instance pointer and
the callee dereferenced it — `tuple(v)`, `sorted(v)`, `bytes(v)`, `reversed(v)`
and `sum(v)` all SEGFAULTED."*

**This is not a regression** — before the fix that same program stored a raw
variant into an 8-byte slot and read garbage, which is not better. And the
checked entry point (`pyvarobj_arg`) cannot simply be substituted: it raises,
and raising here would turn a wrong ANNOTATION into a runtime abort where
CPython would have run the program. But the honest statement is that the fix
trusts the annotation, and an annotation is exactly the thing a user gets wrong.
The diagnostic proposed above — refuse the `tyClass`-slot / `tyVariant`-RHS pair
at COMPILE time where the RHS type is knowably not that class — is the thing
that would close it, and it is still unbuilt.

## Log
- 2026-09-15 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit fc646c17a.
