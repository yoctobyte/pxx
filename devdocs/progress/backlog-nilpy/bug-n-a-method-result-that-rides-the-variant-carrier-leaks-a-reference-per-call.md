---
type: bug
track: N
prio: 85
status: open
slug: bug-n-a-method-result-that-rides-the-variant-carrier-leaks-a-reference-per-call
---

# A method result that rides the VARIANT carrier leaks a reference on EVERY call

`return self.q` leaks +1 refcount per call. So does `return self.a.b`,
`return self.rows[0]` and `return self.lines[a:b]`. `return self` and
`return Q()` are clean. **The discriminator is the CARRIER, and it is visible in
one field of the AST.**

This is NOT the discarded-result bug
(`bug-n-a-freshly-allocated-value-whose-result-is-discarded-is-never-released`).
It leaks when the result is BOUND, which is the common spelling — binding is
what made that other ticket's `me_bound` row clean, and it does not rescue this
one.

Measured 2026-09-15, compiler `f5c08154dcac1f53`, CPython 0 on every row.

## THE CARRIER IS THE WHOLE STORY

`PXXDBG=a.ast` on six getter calls, reading the result type tag off the
`AN_VIRTUAL_CALL` node (`tk`):

| method | returns | `tk` | | leaks |
|---|---|---|---|---|
| `g_obj` | `self.q` | **22** `tyVariant` | | **yes** |
| `g_chain` | `self.mid.leaf` | **22** | | **yes** |
| `g_index` | `self.rows[0]` | **22** | | **yes** |
| `g_slice` | `self.lines[1:3]` | **22** | | **yes** |
| `g_self` | `self` | 6 `tyClass` | | no |
| `g_fresh` | `Q()` | 6 `tyClass` | | no |

An attribute read, a chained attribute read, an index and a slice all come back
through the VARIANT carrier. `self` and a constructor result do not. **Every
variant-carried row leaks and no tyClass row does.**

## objtrace, ONE CALL PER SHAPE, NET OF THE REBIND RELEASE

| shape | retains | releases | net |
|---|---|---|---|
| `return self.q` | 2 | 1 | **+1** |
| `return self.mid.leaf` | 2 | 1 | **+1** |
| `return self.rows[0]` | 3 | 2 | **+1** |
| `return self.lines[1:3]` | 1 alloc + 1 retain | 1 | **+1, ends at rc=1** |
| `return self` | 1 | 1 | 0 |
| `return Q()` | 1 alloc | 1 | 0 |

Depth and indexing change the retain COUNT and never the net. A DIRECT attribute
read at the call site (`k = h.q`) emits exactly ONE retain and is clean — so the
attribute read itself is correct and it is the method RETURN path that adds the
second one. The consumer is retaining a result that already arrives owned, in a
frontend whose stated invariant (ir.inc, the argument-spill comment) is *"all
NilPy results are owned + the consumer borrows"*.

## SCALARS ARE FREE, AND THAT MATTERS FOR RANKING

`return self.level` (float), and the same for int and bool, shows **no object
traffic at all** in objtrace and 0 bytes/call. A variant-boxed scalar allocates
nothing and retains nothing. So only the object-returning accessors are in
scope.

## RSS IS BLIND TO THIS WHENEVER THE RECEIVER OUTLIVES THE LOOP -- READ THIS BEFORE QUOTING A ZERO

The first measurement taken here used a module-level `h` built once and reported
`return self.q` at **0 bytes/call**, i.e. "clean". That is wrong. objtrace on the
same program, five calls:

```
rc 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 ...
```

Two retains and one release per call, forever; the object can never be freed. A
leaked REFERENCE allocates nothing, so RSS only shows BYTES when the referent is
fresh per iteration. **A 0 in an RSS column does not retire a row here** — this
is the third time this family has produced a confident wrong "clean" from an RSS
table, and the ticket above records the other two.

The slice row is the exception and the expensive one: it allocates a fresh
backing buffer per call, so it IS RSS-visible at **200 bytes/call**.

## REPRO

`devdocs/progress/repro-n-a-variant-carried-method-result-leaks.npy`

## WHY 85

Getters are ubiquitous and this needs no unusual spelling — no discard, no
conditional, just `return self.something` consumed normally. Found while
answering a lekkerzeilen census: 27 `return self.<attr>` sites across 21 methods
in that package, plus a wide family of `@property` accessors returning
`self.a.b` that the narrow grep missed. `Vessel.state` is read inside a physics
step running at 120 Hz, and `Tab.shown` returns a SLICE per visible panel per
frame — the 200 b/call row.

## LOCATED -- IT IS THE CALL SITE, NOT THE RETURN, AND THERE ARE TWO DEFECTS

objtrace, three shapes in one program on one long-lived referent, so the
refcount is cumulative and every step is visible:

```
A: a = h.q        direct attribute read, BOUND   R rc 1->2        1 retain, 1 release   BALANCED
B: h.give()       getter call, DISCARDED         R rc 2->3        1 retain, none        LEAKS +1
C: c = h.give()   getter call, BOUND             R rc 3->4, 4->5  2 retains, 1 release  LEAKS +1
```

Row A settles the return: **the retain emitted on the way out of `give()` is
CORRECT.** Boxing `self.q` -- a borrowed lvalue -- into the result variant must
take its own +1, and that is the `tyClass` -> variant arm doing its job. What it
produces is an owned +1 handed to the caller, exactly as
`IRNodeOwnsFreshCallResult` and the frontend's stated invariant both say.

**DEFECT 1 -- THE BIND RETAINS A RESULT THAT ALREADY OWNS ITS +1.**
`ir_codegen.inc:11670`, in `IR_VAR_STORE`'s `tk = tyVariant` arm (the 16-byte
variant-to-variant copy):

```pascal
IREmitNode(IRB[node]);                 { rax = src addr }
EmitVariantRetain;                     { <- UNCONDITIONAL }
```

The two arms directly beneath it in the same `case` do not do this. The
`tyAnsiString` arm asks `IRNodeOwnsManagedStr`; the `tyClass` arm asks
`IRNodeOwnsManagedObj`. Each carries a comment saying in its own words that a
CALL result is *"already OWNED (+1, ownership transfers)"* and that retaining it
*"leaked one handle per boxed call result"*. **The variant-to-variant copy is the
third member of that family and never got the discrimination**, so a
variant-carried call result is retained as though it were a shared lvalue.

The ticket cited beside the `tyAnsiString` arm --
`bug-a-runtime-variant-heap-grows-unbounded` -- is the tell: this same defect was
found and fixed for strings, then for objects, and the variant copy was left.

**DEFECT 2 -- A DISCARDED VARIANT RESULT IS NEVER RELEASED** (row B).
`IRDropManagedResult` has a `tyAnsiString` arm, a dyn-array arm, and now a
`tyClass` arm. It has no `tyVariant` arm, so the owned +1 on a discarded
variant-carried result is dropped on the floor.

## THE ORDER MATTERS, AND THE NATURAL FIRST PATCH IS THE ONE THAT CANNOT WORK

The obvious shape for defect 2 is the one the `tyAnsiString` arm uses: spill into
a hidden local of that type and let the rebind/scope-exit release it. **That
cannot work while defect 1 stands**, because the spill IS a variant-to-variant
copy -- it would retain the result (a second +1) and release only the previous
iteration's, so the original +1 still leaks and a new one joins it. Fix the copy
first; then the spill takes ownership and the next overwrite frees it.

## RETRACTED 2026-09-15 -- "THE HARD PART" AS BANKED WAS WRONG, TWICE OVER

The section that stood here claimed the source operand at the copy site is *"the
ADDRESS of a variant slot, not the call"*, that
`IRNodeOwnsFreshCallResult(IRB[node])` *"answers False and cannot be used
directly"*, and prescribed a `SymIsCtorResultTemp`-style flag. It also told the
next reader to probe the site before building on it. That instruction was the
only part that survived contact.

**Probe at the site** (`WriteLn` of `IRKind[IRB[node]]` and both predicates,
compiler rebuilt to its own fixedpoint, `converged after 1 round(s)`):

```
VCPROBE srckind=30 srcA=28 ownsfresh=1 ownsobj=1
```

`srckind=30` is `IR_VIRTUAL_CALL` -- the call ITSELF, not a temp address -- and
`IRNodeOwnsFreshCallResult` answers **True**. There is no spill, no flag needed,
and the prescribed fix was a solution to a problem that does not exist. So the
guard looked like a one-liner, the same shape the two arms below it already use:

```pascal
if not IRNodeOwnsManagedObj(IRB[node]) then
  EmitVariantRetain;
```

**Built, that guard SEGFAULTS.** Which is the real finding, and it is the
opposite of a hard part being absent.

## THE ACTUAL DEFECT: THE VARIANT CARRIER HAS TWO CALL CONVENTIONS

Measured at `cfee5d6255237332` (landed) against the guard build `745b82d21c1b`:

| shape | callee returns | needs caller retain? |
|---|---|---|
| `c = h.give()`, `return self.q` / chained / indexed / sliced | **OWNED (+1)** | NO -- retaining is the leak |
| `nm, fn = <list element>`, `open()`, pylist/tuple internals | **BORROWED** | YES -- not retaining is a use-after-free |

`IRNodeOwnsFreshCallResult` answers **True for both**, because it is a claim
about the NODE SHAPE ("is this a fresh call result") and not about the callee's
convention. Its own header says so: *"any fresh call result"*. That assumption
is TRUE on the string and tyClass carriers and FALSE on the variant one.

**Why the OWNED half owns.** The IR of the callee settles it -- `return self.q`
is ITSELF an `IR_VAR_STORE tk=22` whose source is a `load_mem`, so it takes the
very same unconditional-retain arm and returns +1. Correct: `self.q` is
borrowed, and the result must own. The caller then hits the SAME arm with an
`IR_VIRTUAL_CALL` source and retains a second time. That second retain is the
leak, and the two retains are emitted by one line of code.

```
H.g_obj:  3: load_mem a=2 tk=6
          4: lea a=544 [sym=$pyresult] tk=17
          5: var_store a=4 b=3 c=6 tk=22      <- retains here, correctly
```

Note `H.g_self` (`return self`) returns on tk=6, a DIFFERENT carrier, and is not
part of this at all -- it reads 0 bytes/call throughout and is a control, not a
case.

**This is the same distinction `2dc0d6878` drew for the tyClass arm of
`IRDropManagedResult` this same week**, where the discriminator is
`UnitIsPyModule(ProcUnitIdx[callee])`: a Pascal library facade's result is
BORROWED, a NilPy method's is OWNED. I solved it once, in this family, and then
reached for a node-shape predicate that cannot express it.

## THE POSITIVE CONTROL THIS TICKET WAS MISSING

`test/test_nilpy_a_borrowed_variant_result_is_not_moved.npy` -- committed here
because the over-broad fix is the OBVIOUS fix and the next reader will write it.

The existing repro cannot catch it usefully: under the broken guard it
segfaults, but only after a 12000-iteration warmup of twelve unrelated shapes,
and the visible symptom was a corrupted `print` (`meas meas` for
`meas LONGLIVED obj`) that varies run to run. Every row of it passes in
ISOLATION -- I bisected all nine, all rc=0 -- so a reader who minimises the way
one normally minimises concludes the guard is fine.

The control is four lines of ordinary Python and fails LOUDLY and
DETERMINISTICALLY:

```python
rows = [("alpha", f1), ("beta", f2)]
for i in range(4000):
    for nm, fn in rows:
        ...
```

guard build: `IndexError: tuple index out of range`. Landed: `UNPACK OK`.
A tuple unpack in a for-loop is not an exotic shape; it is what the repro's own
driver loop is written in, which is why the repro crashed in its driver rather
than in any row under test.

## WHAT THE FIX NEEDS, RESTATED

Carry the callee's PROVENANCE to the variant-copy site -- the thing
`IRDropManagedResult` already reads at AST level via `ASTIVal[astNode]` as the
callee proc index. At the `IR_VAR_STORE` arm in `ir_codegen.inc` that index is
not in hand for `IR_VIRTUAL_CALL` (`IRA` is a slot, not a proc), so the
discrimination belongs where the AST is still available -- flag the IR node at
BUILD time in `ir.inc` and let the emitter read the flag. `SymIsCtorResultTemp`
remains the worked precedent for the flagging TECHNIQUE; it was the wrong
diagnosis, not the wrong pattern.

**Defect 2 (no `tyVariant` arm in `IRDropManagedResult`) is unchanged and still
real**: a discarded `h.give()` shows +1 with no release. But it is now clear
that Defect 2 must not be fixed by releasing every discarded variant call result
either -- a discarded facade call returns borrowed, and releasing it is the same
use-after-free from the other end. Both defects need the same provenance bit,
which is an argument for building that bit ONCE rather than twice.

## ATTEMPT 2 ALSO FAILED, AND IT NARROWS THE QUESTION TO ONE SENTENCE

Built the provenance discrimination the section above prescribes: read the
callee proc index off the call node (`IRA` for `IR_CALL`, `IRC` for
`IR_VIRTUAL_CALL` -- both already operands, no new state) and ask
`UnitIsPyModule(ProcUnitIdx[cp])`, exactly as `IRDropManagedResult`'s tyClass
arm does. Self-hosts, `converged after 1 round(s)`, binary `37acfdbcc84d`.

**Results, all four fixtures:**

| | pre-fix `cfee5d62` | node-shape guard `745b82d2` | provenance guard `37acfdbc` |
|---|---|---|---|
| VARCARRY (the leak) | FAIL, 5 rows | -- | **OK** |
| BORROWVAR (the use-after-free) | OK | IndexError | **OK** |
| Track N tier | green | -- | **SEGV** |

It fixes the leak, keeps the borrowed half alive, and **breaks
`test_nilpy_a_module_qualified_def_is_a_value_across_modules`**, which the
NilPy tier caught. Under `-dPXX_HEAP_DEBUG`:

```
pxx-heap: RELEASE of a FREED object 0x00007d07ad0004a8
pxx-heap: RETAIN of a FREED object  0x00007d07ad000230
```

`rax` at the fault holds `0x39202c38202c3753` -- ASCII text -- so the block was
freed and its memory reissued to a string. A genuine use-after-free, not a leak.

## WHY THE UNIT IS THE WRONG INSTRUMENT, MEASURED RATHER THAN ARGUED

`UnitIsPyModule` is a proxy for "did this callee's return leave +1", and the two
come apart because **NilPy has TWO return paths onto the variant carrier**, not
one. From `PXXDBG=a.ir` on the two callees:

```
H.give   (main program, `return self.q`)
  3: load_mem a=2 tk=6
  5: var_store a=4 b=3 c=6  tk=22      <- c=6: source is tyClass, BOXING path

via      (module, `return h()`)
  7: call a=1852 c=6 tk=22             <- pyvar_callv0, a Pascal facade
  9: var_store a=8 b=7 c=22 tk=22      <- c=22: variant-to-variant COPY path
```

`IRC` on the store is the SOURCE KIND. The arm under guard is only the `c=22`
copy; the `c=6` boxing arm is a different piece of code that retains
regardless. So `H.give` owns its result for a reason that has nothing to do with
its unit, and `via` owns or borrows its result for a reason that has nothing to
do with its unit either. **The unit test agreed with the truth on the rows I had
measured and disagreed on the rows I had not**, which is the definition of a
proxy rather than an instrument.

Confirming that the seam is exactly here and not elsewhere: restricting `owned`
to `ProcUnitIdx < 0` (main-program procs only) turns all three fixtures green --
tier rc=0, VARCARRY OK, BORROWVAR OK. **That is NOT landed and must not be.** It
is the same proxy with the failing half deleted, it leaves every module-defined
method leaking, and shipping a predicate known to be wrong in a case nobody can
explain is the compiler-appeasement workaround CLAUDE.md refuses. It is recorded
because it localises the seam for the next attempt, not because it is a
candidate.

## WHAT THE FIX ACTUALLY NEEDS, IN ONE SENTENCE

**Whether a call result arrives owned is a property of the CALLEE'S OWN RETURN
LOWERING, so it must be recorded when that return is lowered -- not inferred at
the call site from anything about the callee.**

Concretely: a per-proc flag (`ProcVariantResultOwned`, the shape
`ProcRetFixedArrBytes` and `ProcUnitIdx` already have in defs.inc) set at the
point the return's `IR_VAR_STORE` is built in `ir.inc`, recording whether that
store left +1. Pascal facades never go through NilPy return lowering and so
default to False -- borrowed, retain -- which is the safe default and the one
that is correct for them today.

**The ordering question is the real work and is why this is not a small
change**: a call site can be lowered before its callee. `PyMarkVariantParamsByRef`
is the in-tree precedent for exactly this problem -- it moved an ABI decision to
signature-REGISTRATION time for the same reason -- and its own ticket
(`done/bug-n-a-callee-declared-below-its-caller-gets-the-argument-by-the-wrong-abi`)
records what goes wrong when the decision is read from the body instead. Read it
before starting.

## DO NOT ATTEMPT A THIRD FIX FROM A PREDICATE THAT MERELY ANSWERS

Three attempts in this family have now failed the same way: the probe answers,
the answer is correct, and the question is wrong.

1. banked: "the operand is a temp address, the predicate cannot answer" -- it is
   the call, and it answers.
2. `IRNodeOwnsManagedObj` -- answers True, and asks about node SHAPE.
3. `UnitIsPyModule` -- answers, and asks about the callee's FILE.

**The next patch must be justified by what the CALLEE'S RETURN DID, and the
justification must be a measurement of that, not of a correlate.** Both
fixtures must be run, and so must the NilPy tier -- the tier is what caught
attempt 2, and neither fixture could have.

## THE ORIGINAL SECTION, KEPT SO THE RETRACTION IS CHECKABLE

## THE HARD PART, AND IT HAS A WORKED PRECEDENT IN-TREE

At the copy site the source operand is the ADDRESS of a variant slot, not the
call: a variant-returning call is materialised into a temp, so `IRB[node]` is
that temp's address and `IRNodeOwnsFreshCallResult(IRB[node])` answers False. It
cannot be used directly.

**`SymIsCtorResultTemp` already solves exactly this**, and `defs.inc:4401`
describes this failure in its own words: *"the spill hides the construction from
every consumer: the AST-level arms see AN_CALL and are right, the IR-level
variant store sees IR_LOAD_SYM and retained a second time."* The remedy there was
to FLAG the temp at the one place it is minted and let `IRNodeOwnsManagedObj` ask
about the flag. Same shape here: flag the hidden temp that receives a
variant-typed call result, and give the variant-copy arm a predicate that asks.

**VERIFY THE OPERAND SHAPE WITH A PROBE AT THE SITE BEFORE BUILDING THAT.** Print
`IRKind[IRB[node]]` and what the operand resolves to. Two claims in this
family's history were wrong because they were read off a probe run against a
`compiler/pascal26` that was not the fixedpoint of its own sources; do not add a
third.
