---
slug: feature-pascal-management-operators-nested-and-array
title: "Management operators do not reach an array element or a nested field"
track: P
prio: 35
type: feature
status: working
owner: frankA
blocked-by: []
summary: "FIXED ARRAYS ARE DONE 2026-09-07 (frankA); ONE ARM LEFT AND IT IS NOT THIS PASS'S. Reached and managed now: a managed record through a FIELD at any depth, through an ELEMENT of a fixed array SYMBOL, through an ELEMENT of a fixed array FIELD, and -- new -- through a MULTI-DIMENSIONAL fixed array in either position, to any dimension count. Storage is flat row-major and the recorded extent is the FLAT element count, so one loop walks any dimensionality; what changes with the dimension count is the INDEX SPACE, and that is the whole finding. MEASURED, not derived: a synthesised single-subscript AN_INDEX over a 1-D array is lowered in SOURCE space (the low bound is subtracted, so array[2..3] is walked 2..3) and over an N-D array in FLAT space (nothing is subtracted, so it is walked 0..count-1). Walking an N-D array from its own low bound writes one element PAST the array and leaves the first uninitialized -- array[1..2, 5..7] printed body 001234 against fpc's 012345 and finalized a sixth element holding the neighbouring scalar field. A 0-BASED FIXTURE CANNOT SEE ANY OF THAT: with the dimension guard removed, array[0..1, 0..2] walked flat matches fpc element for element, because a flat index and a dimensional index coincide at origin zero, so every multi-dim fixture here declares non-zero low bounds. Verified against fpc 3.2.2 byte for byte on four shapes no two of which share a mechanism (2-D symbol, 2-D field beside a scalar neighbour, 3-D field with three non-zero lows, 2-D field whose element holds its own 1-D array field), on all five runnable targets. STILL REFUSED AND DELIBERATELY NOT THIS TICKET'S WORK: a DYNAMIC array, symbol or field. Measured against fpc 3.2.2, its Initialize runs INSIDE SetLength on elements that come into existence and Finalize inside it on ones that stop, with only the survivors finalized at scope exit -- so a scope-entry loop over Length() initializes ZERO elements and never sees one created later. That arm needs [[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]], not a desugar, and the refusal text now says so. CLASS fields left for [[feature-pascal-management-operators-on-a-class-field]]. ORDER RULES UNCHANGED AND STILL MEASURED: across NESTING levels Initialize is POST-order and Finalize PRE-order; across ARRAY ELEMENTS both run ASCENDING, in flat storage order for a multi-dimensional one. CORPUS: tmoperator7 is still not cleared -- its array is DYNAMIC."
---

# Management operators do not reach an array element or a nested field

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** working
- **Follows:** [[feature-pascal-class-management-operators]] — slice 3 refuses
  these shapes rather than compiling them silently.

## Symptom

    error: an array of a record with a management operator is not supported yet
    error: a field of a record with a management operator is not managed yet

`class operator Initialize/Finalize` fires for a variable **of** the managed
record type. It does not fire for:

- `arr: array[0..1] of TFoo` — FPC initializes and finalizes every element;
- `b: TBar` where `TBar` has a `TFoo` field, at any depth;
- a class whose field is a managed record (same check, `tyClass` arm).

Measured against FPC 3.2.2, which does all three:

    var b: TBar;              ->  init / ... / fin 7
    var arr: array[0..1] ...  ->  init 0 / init 1 / ... / fin 0 / fin 1

The second row read `fin 3 / fin 0` until 2026-09-06 — descending, which is
what a scope-exit rule looks like if you assume arrays unwind the way locals
appear to. **fpc does not reverse array elements.** Corrected against 3.2.2's
own output, which is now `test/test_mgmt_operators_array.expected` byte for
byte. The pre/post-order rule that DOES hold across nesting levels is a
different rule and still applies within each element.

## Why it is refused rather than skipped

A record whose declared invariant simply never runs is worse than a program
that does not compile — the failure would be a plausible wrong value far from
the cause, which is the expensive shape in this repo. So the scan errors and
names this ticket.

## Root cause

`WrapManagementOpsRange` (`compiler/parser.inc`) is a **per-symbol** desugar:
for each managed local/global it emits `Initialize(v)` and a `try..finally
Finalize(v)`. FPC gets the recursion free because it drives the whole thing off
the type's RTTI. Reaching an element needs a synthesised loop; reaching a field
needs a synthesised field path.

## Sketch

Generalise the emitter from "a symbol" to "an lvalue node + its type":

- record field -> a field-access node, recursing on the field's recId;
- static array -> a synthesised `for i := lo to hi do Op(base[i])`, which the
  AST can already express;
- dynamic array / class instance field -> a runtime walk, i.e. genuinely the
  RTTI shape FPC uses; probably out of scope for the desugar and the point at
  which a Track A ticket for record RTTI descriptors is the right answer.

Do the two static cases first — they are what the conformance tests use — and
keep the refusal for the rest.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + the repro programs diffed
against FPC 3.2.2 + `tools/gate.sh quick`. The refusal fixtures under `test/`
must be converted from "refused" to "matches FPC" as each case lands.

## 2026-09-06 (frankS) — the two corpus rows, one per arm

Measured at `88a0b3d93835`:

| row | line | arm |
| --- | --- | --- |
| `tmoperator4.pp` | 81 | `a field of a record with a management operator is not managed yet` |
| `tmoperator7.pp` | 101 | `an array of a record with a management operator is not supported yet` |

One row per arm, which is the argument for keeping both arms in one ticket: a
fix that lands only the field path leaves a live corpus row on the other
refusal, and the two share `WrapManagementOpsRange`.

**tmoperator7 did not reach line 101 until today.** It stopped at line 29 on
`undefined variable (InitializeCount)` — a `class var` of the record, named
unqualified from inside `class operator TFoo.Initialize`, which pxx parsed as a
bare global function with no record scope. That was a NAME-RESOLUTION defect
with nothing to do with management operators, and the row's skip reason recorded
it as *"the management-operator cluster"* because that is what the file is about.
Fixed in the same commit as this note. **A row's skip reason is a claim about
where it stops, and where it stops is a claim about one line — everything past
it is unverified.**

## What is NOT in this ticket

`System.InitializeArray` / `FinalizeArray` — the RTTI-driven form
(`InitializeArray(P, TypeInfo(TFoo), N)`) that tmoperator2/3/9 use. This
ticket's own Sketch predicted it: *"dynamic array / class instance field -> a
runtime walk, i.e. genuinely the RTTI shape FPC uses; probably out of scope for
the desugar and the point at which a Track A ticket for record RTTI descriptors
is the right answer."* That ticket now exists and has three corpus rows:
[[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]].

## 2026-09-06 (frankA) — the record NESTED-FIELD arm lands, and the class arm is a different mechanism

**Done: a record that CONTAINS a managed record, at any depth.** The desugar
walks the field table and builds a field path per call (`AN_FIELD` over a cloned
base), so `b: TBar` with `TBar.f: TFoo` now initializes and finalizes exactly as
fpc does. Two levels deep works, and so does a record with BOTH its own operator
and a managed field.

**THE ORDER IS NOT UNIFORM AND I WOULD HAVE GUESSED IT WRONG.** Measured against
fpc 3.2.2 before writing any of it:

| | order |
| --- | --- |
| `Initialize` across nesting | **POST**-order — the fields, then the record's own operator |
| `Finalize` across nesting | **PRE**-order — the record's own operator, then the fields |
| both, within one level | declaration order **FORWARD** |

The two halves look contradictory side by side and are both real: construct /
destruct symmetry ACROSS levels, and no reversal at all among siblings, array
elements or the locals of a scope. `a`, `n.p`, `n.q`, `b` finalize 0,1,2,3 — fpc
does not reverse them. A test asserting only "Initialize and Finalize both ran"
passes with either rule inverted, so every row in the new fixture prints a
distinguishable number.

**THE CLASS ARM IS NOT "the same check, tyClass arm" — it is a different
LIFETIME and therefore a different insertion point.** Measured: for `c: TCls`
whose field is a managed record, fpc runs the field's `Initialize` inside
`TCls.Create` and its `Finalize` inside `Free`. Nothing happens at scope entry
or exit. A scope-bound `try/finally` — which is all this pass can emit — would
finalize a LIVE heap object at every scope exit and would never run for an
object that outlives the scope. Wrong in both directions, so it stays refused
and it does not belong in this desugar at all; it belongs on the constructor and
destructor paths.

**AND THE CORPUS EVIDENCE WAS ATTRIBUTED TO THE WRONG ARM.** This ticket's
summary cites *"tmoperator4 (line 81, the nested-field arm)"*. tmoperator4's
`TA` and `TB` are **classes** — it is the class-field shape, not the record one.
So the demand sits on the arm that is still refused, and the record nested-field
arm that just landed had **no corpus row at all**. That is not an argument
against having done it: fpc does it, the refusal was reachable from ordinary
source, and it is the smaller half of what was one ticket. It is an argument for
not reading the corpus citation as covering both arms, which is exactly what
"one row for each arm" invited.

**Still refused, and each now has its own fixture naming why:** an array of a
managed record (the symbol case), an ARRAY FIELD inside a record at any depth
(same missing loop — and `UFldTk` carries the ELEMENT kind, so a guard reading
only the kind lets it through silently; `UFldIsArray` is what separates them),
and the class case above.

**The old `test_mgmt_operators_field_refused` fixture EXPIRED and was re-aimed
rather than deleted.** It asserted that a plain `f: TFoo` field is refused, which
is now false. A fixture that asserts a NEGATIVE turns red the day someone
implements the thing, and it is the one kind of test whose failure means
"succeeded". Re-pointed at the array-field shape; a new
`test_mgmt_operators_class_field_refused` covers the class one, with the
Create/Free measurement in its header so the next reader does not fold it back
in.

## 2026-09-06 (frankA) — the FIXED-ARRAY arm lands, and what it is refuted by

**Done: `arr: array[lo..hi] of TFoo` initializes and finalizes every element**,
as a proc local and as a program global, matching fpc 3.2.2 byte for byte for
the local case (`test_mgmt_operators_array`).

`AppendManagedArrayOps` synthesises `k := lo; while k <= hi do begin <element
ops>; k := k + 1 end`. The element ops are **the same `AppendManagedFieldOps`
walk a plain record local gets**, over an `AN_INDEX` base instead of an
identifier — so an array of records that themselves hold managed fields works
without a second mechanism, and the nesting order rule keeps applying inside
each element.

### The order, measured before it was written

fpc 3.2.2, `b: array[0..1] of TBar` where `TBar` has both its own operators and
a `TFoo` field:

    init Foo 3 / init Bar 4 / init Foo 5 / init Bar 6
    fin  Bar 4 / fin  Foo 3 / fin  Bar 6 / fin  Foo 5

Two rules, and they are not the same rule:

- **across ARRAY ELEMENTS: ascending, both directions.** `b[0]` finalizes before
  `b[1]`. Nothing is reversed on the way out.
- **within one element: post-order in, pre-order out** — the nesting rule this
  ticket already had, unchanged.

The ticket's own Symptom section predicted descending and has been corrected
in place. A test asserting only that both elements ran would have passed either
way, which is why every row prints a distinguishable number.

### Two things the fixture is aimed at that a smaller one would miss

**SOURCE index space.** `test_mgmt_operators_array` declares `array[3..5]`, not
`array[0..2]`. The loop builds an `AN_INDEX` node read exactly the way `a[3]` in
the source is, so it must run 3..5. A loop hard-coded to `0..n-1` is correct for
every 0-based declaration — which is every array anyone writes by reflex — and
silently initializes three slots that are not the array's for the other one.
The bounds come off the symbol: `ConstVal` is the LOW bound (AllocArray stores
it there) and `ArrLen` the extent.

**The refusal and the emission are one predicate.** `SymIsLoopableManagedArray`
is spelled once and both read it. A shape the refusal lets through and the
emission skips is a declared Initialize that silently never runs — which is the
exact defect `regression-test-core-test-mgmt-operators` was written for, and it
arrived last time through two conditions that were *supposed* to agree.

### The global array diverges from fpc, in the direction of running more

Measured on the fixture itself: fpc 3.2.2 prints `body 000` and no operator line
at all for a global array, while for a plain global *record* it runs Initialize.
So the omission is about the array, not about globals. `_global_array.expected`
is therefore ours rather than fpc's, and the header carries both divergences —
the second (no Finalize for a record global) being the position already chosen
in `test_mgmt_operators`'s header, which this inherits.

### Still refused, each with its own fixture

`array_refused` is now the DYNAMIC case and `multidim_array_refused` the 2-D
one: two clauses of one predicate, so neither row can stand in for the other —
a 2-D array has a fixed `ArrLen` and would sail past a dynamic-only check. Both
fixtures were re-aimed rather than deleted, because a test whose whole claim is
"we do not support X" goes red the day someone implements X.

**SUPERSEDED 2026-09-07 — see the multi-dimensional section at the end of this
ticket.** `multidim_array_refused` and `multidim_array_field_refused` expired
when the flat walk landed and were retired into the positive fixture
`test_mgmt_operators_multidim_array`; `array_refused` and `field_refused` remain
and are the DYNAMIC pair. The sentence above is kept because the reasoning in it
is what the retirement had to answer, not because it still describes the tree.

### The corpus row does not clear, and that is the honest reading

`tmoperator7` moved from line 101 to **line 117** and still stops on this
ticket's refusal — its array is `SetLength(FoosObj, ...)`, i.e. DYNAMIC. The
fixed-array arm cannot clear it. Advancing 16 lines is real progress through the
file and it is not a closed row; whoever takes the dynamic case owns that one.

## 2026-09-06 (frankA) — the class arm left this ticket

The `tyClass` refusal is now
[[feature-pascal-management-operators-on-a-class-field]], with tmoperator4 as
its corpus row. It is not a remaining case of this mechanism: a class field's
operators run at `Create`/`Free`, and everything `WrapManagementOpsRange` emits
is scope-bound by construction. What stays here is the ARRAY family — dynamic
and multi-dimensional — plus the array-field-inside-a-record shape, all three of
which are the same missing loop rather than a different lifetime.

## 2026-09-07 (frankA) — the ARRAY FIELD arm lands, and the guard that nearly certified itself

`arr: array[0..1] of TFoo` **inside** a record is managed now, at any depth, and
so is the mutual case — an array SYMBOL whose element holds an array FIELD.

### What changed, and why it is one mechanism and not a second one

`AppendManagedArrayOps` took a **symbol index** and built its own
`GenMakeIdent`. It now takes a **base NODE** and clones it, so the identical
procedure serves an `AN_IDENT` base (the array symbol) and an `AN_FIELD` base
(the array field). `AppendManagedFieldOps` calls it for a loopable array field;
`AppendManagedArrayOps` already called `AppendManagedFieldOps` for the element's
own fields. The two are therefore **mutually recursive** and one is
forward-declared. That is the whole change on the emission side.

The low bound comes from the **field** table — `UFldArrDimLo[fi*MAX_ARR_DIMS]` —
not from `Syms[].ConstVal`, and it is the SOURCE index: `f: array[2..3] of TFoo`
runs 2..3, because an `AN_INDEX` under an `AN_FIELD` base is lowered against
that field's own `RecFieldArrLo` (`ir.inc`, the `{$R+}` field-array branch names
the same table).

`FldIsLoopableManagedArray` is the field-table mirror of
`SymIsLoopableManagedArray` and is asked in **exactly two places** — the refusal
and the walk. That is the same reason the symbol-side predicate exists: a shape
the refusal lets through and the walk skips is a declared `Initialize` that
silently never runs, and the disagreement is silent in only one direction.

### The order was measured again rather than carried over

An array FIELD sits at the same place in the pre/post-order rule as a plain
nested field, and its elements run ascending in both directions. fpc 3.2.2 on a
record with its own operator and an `array[2..3] of TFoo` field:

    init Foo 2 / init Foo 3 / init Baz        <- elements ascend, then self
    fin  Baz   / fin  Foo 2 / fin  Foo 3      <- self, then elements ascending

### THE PART WORTH READING: the multi-dimensional refusal nearly certified itself

I wrote the multi-dim field fixture with `array[0..1, 0..2]`, asserted in its
header that deleting the `UFldArrNDims <= 1` test would turn it into an
out-of-bounds write, and then — because a guard I add has to SHOW its necessity
— deleted the test and rebuilt.

**The 0-based version compiled, ran, and matched fpc 3.2.2 element for
element.** `UFldArrLen` is the FLAT count (6 for `[0..1, 0..2]`) and the field's
low bound is 0, so a 1-D loop over 0..5 addresses exactly the six elements. The
flat loop is *correct* there.

It is wrong the moment the OUTER dimension starts anywhere but zero. Same
poisoned compiler, `array[1..2, 5..7]`:

| | fpc 3.2.2 | pxx with the NDims test removed |
| --- | --- | --- |
| body | `012345` | `001234` |
| last finalize | `fin 5` | `fin 9` — the neighbouring `k` field |

So the guard is load-bearing, and **the fixture I first wrote could not have
shown it**: it would have gone on passing after the removal and certified it.
The committed fixture declares `array[1..2, 5..7]` and its header says why.

This is the "choose a probe whose right answer differs from the default" rule
arriving through a new door — here the *default* is not a type's zero, it is the
**zero low bound**, which makes a flat index and a dimensional index coincide.
Any assertion about multi-dimensional indexing written on a 0-based array is
measuring nothing.

### The refusals now name which obstacle

`RecContainsUnreachableManagedField` returns a reason (`UMF_DYN` / `UMF_NDIMS`)
and `UnreachableManagedFieldMsg` spells the two sentences once. Both refusals
cite this ticket, so a Makefile row grepping only the slug would let either
stand in for the other and could not tell "the dynamic arm regressed" from "the
multi-dimensional arm regressed" — an expected-failure row passes on ANY refusal
unless it reads which. The two `test-core` rows grep the reason.

### Verification, and what does NOT back it

- **fpc 3.2.2 is the oracle**, and `test/test_mgmt_operators_array_field.expected`
  IS its output. Five arms: array field in a plain record; array field beside an
  own operator with a non-zero low bound; an array field one nesting level down;
  an array field whose ELEMENT is itself a nested managed record; and the mutual
  recursion (an array symbol whose element holds an array field).
- **The fixture is its own positive control.** Every arm prints back the `n`
  that `Initialize` is the only writer of. The defect class here is *a declared
  invariant that never runs*, which passes every value check unless the value is
  read back — the same shape as a leak passing an `expect_same` row.
- **The before-baseline is a refusal**: the pinned compiler rejects the fixture
  outright, so no arm of it can be a coincidence of the new build.
- **All five runnable targets** — x86_64, i386, aarch64, arm32, riscv32 —
  produce the same text as fpc. Wired as `test-mgmt-operators-cross-target` and
  enrolled in Track T's `full` tier.
- **NO tstate verdict backs any of this.** Seven has produced sixteen
  `infra … no report (rc=1)` rows in the last forty commits, on both the native
  and full rungs, so breadth is down and a quiet tstate here is not a pass. The
  fpc oracle, the five-target run and the pinned control are the whole evidence.
- The three fixed-array `tmoperator` corpus rows are **not** advanced by this:
  tmoperator7's array is dynamic.

### What is left in this ticket

Exactly two shapes, and they are two clauses of one predicate rather than one
problem: a **dynamic** array (no extent to read — needs the loop built against
`Length()`), and a **multi-dimensional** one (a readable flat extent and a 1-D
loop — needs either N nested loops or a flat loop that indexes flat, which the
low-bound measurement above says is not the same thing). Both apply to a SYMBOL
and to a FIELD, and all four have a fixture.

## 2026-09-07 (frankA) — MEASURED: the dynamic arm does not belong in this pass at all

This ticket's refusal message and its Sketch both say the dynamic case needs
"the loop built against `Length()`". **That is wrong, and it is wrong in a way
that would have produced a plausible half-working feature.** Measured against
fpc 3.2.2, `var d: array of TFoo` with `SetLength` 3 -> 5 -> 2:

```
declared
  init 0 / init 1 / init 2        <- INSIDE SetLength(d, 3)
after SetLength 3 -> 012
  init 3 / init 4                 <- INSIDE SetLength(d, 5), NEW elements only
after SetLength 5 -> 01234
  fin  2 / fin  3 / fin  4        <- INSIDE SetLength(d, 2), REMOVED elements
after SetLength 2
leaving P
  fin  0 / fin  1                 <- at scope exit, the SURVIVORS
done
```

Three separate events, and only the last one is a scope event:

1. **Grow** — `Initialize` on the elements that came into existence.
2. **Shrink** — `Finalize` on the elements that stopped existing.
3. **Scope exit** — `Finalize` on whatever is still live.

A scope-entry loop over `Length(d)` initializes **zero** elements (a dynamic
array is empty at declaration) and never runs for any element created later, so
it would be a declared invariant that never runs — the exact defect this pass
exists to refuse. Building only half of it, the scope-exit finalize, is worse
than refusing: elements would be finalized that were never initialized.

**So the dynamic arm's home is `SetLength`, not this desugar** — and `SetLength`
is a runtime routine holding a pointer and an element size, with no idea what
record it is looking at. That is precisely the descriptor
[[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]]
exists to emit, and this is a FOURTH consumer for it beyond that ticket's three
corpus rows. The refusal text and the Sketch are corrected above; the refusal
itself stays exactly as it is, because refusing remains the right answer here
until the descriptor exists.

**What is left in THIS ticket is therefore one shape, not two**: the
MULTI-DIMENSIONAL fixed array, as a symbol and as a field. Its extent is fully
known at compile time and it needs nested loops rather than a descriptor.

## 2026-09-07 (frankA) — the MULTI-DIMENSIONAL arm lands, and the guard it replaces was measured wrong twice

The refusal I had just written for this shape said "the synthesised loop is
one-dimensional". **It is, and that turns out not to matter**: storage is flat
row-major, the recorded extent is the flat element count, and fpc visits the
elements in that same flat order. One loop is enough at any dimensionality.

### What actually differs, and it is not the loop

**The index space.** Measured, in this order, because each step refuted the
model I had going into it:

| shape | walked from | result |
| --- | --- | --- |
| 1-D field `array[2..3]` | its low bound, 2..3 | correct |
| 2-D field `array[0..1, 0..2]` | flat 0..5 | correct — and so is walking it from its low bound, because they are the same numbers |
| 2-D field `array[1..2, 5..7]` | its low bound, 1..6 | **wrong**: `body 001234` vs fpc `012345`, sixth element finalized over the neighbouring `k` |
| 2-D field `array[1..2, 5..7]` | flat 0..5 | correct |

So a synthesised single-subscript `AN_INDEX` is read in **source** space over a
1-D array and in **flat** space over an N-D one. Both call sites now say that in
a comment, because it is the kind of asymmetry that reads as an accident.

Worth separating from that: a single subscript **written in source** on an N-D
array is neither — it selects a whole ROW through `BuildPartialNDRowIndex`
(measured: `b.f[2]` on a 2×3 lands at element 3). The desugar's node never goes
through that parser path — nothing fills `NDInfo*` or stamps `ASTNDRowSubs` for
it — which is why it is an element index at all.

### The fixture, and why every bound in it is non-zero

`test/test_mgmt_operators_multidim_array.pas`, four shapes no two of which share
a mechanism: a 2-D array SYMBOL (symbol table, `Syms[].ConstVal`), a 2-D array
FIELD beside a scalar neighbour (field table, `UFldArrDimLo` — and `k` is what a
past-the-end write lands on), a 3-D FIELD with all three lows non-zero (the flat
count is a product of three spans), and a 2-D FIELD whose element holds its own
1-D array field (a flat walk nested inside a flat walk). `.expected` is fpc
3.2.2's output. All five runnable targets match it.

The bounds are `1..2, 5..7` and `3..4, 1..2, 7..8` rather than 0-based because a
0-based fixture **cannot fail**: with the dimension guard removed, the 0-based
version matched fpc element for element. That is recorded at length in
`devdocs/dev/handbook-rationale.md`.

### Two negative fixtures expired and were retired rather than deleted on sight

`test_mgmt_operators_multidim_array_refused` and
`..._multidim_array_field_refused` asserted a refusal this commit implements —
the third and fourth expiry in this family. Their shapes were absorbed into the
positive fixture (they are its `sym` and `fld` arms), which is why the files
themselves are gone rather than re-aimed: there was nothing left in that class
to aim them at. The two DYNAMIC rows remain and now read the reason and the
noun, with `holding` in the pattern because "a DYNAMIC array" is a prefix of
"a DYNAMIC array field".

### What is left

One shape: a **dynamic** array, symbol or field. It is not this pass's work —
see the SetLength measurement above — and its refusal cites the RTTI ticket.
Class fields are their own ticket. **Everything fixed is done.**
