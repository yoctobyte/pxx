---
track: A
prio: 75
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankA
tags: [records, equality, cross-target, silent-wrong, rust]
blocked-by: []
summary: "`a = b` on a plain record compares ONLY THE FIRST 8 BYTES on x86-64, aarch64, arm32 and riscv32, and answers FALSE unconditionally on i386. Two records with the same first field and a different last field compare EQUAL -- a wrong TRUE, silently, on four targets; on i386 a record is never equal to a byte-identical copy of itself. Measured 2026-09-06 with a 12-line Pascal program, confirmed through an `if` as well as a WriteLn argument. `ir.inc`'s BINOP lowering leaves `=`/`<>` on records to fall through to the scalar IR_BINOP DELIBERATELY -- its comment says method-pointer compares are legitimate record `=` -- so no general record comparison was ever emitted and the fallthrough compares one machine word. FPC REFUSES the construct (`Operator is not overloaded: \"TR\" = \"TR\"`), so the Pascal side is us accepting more than FPC AND answering wrong, which is a defect regardless. THE RUST FRONTEND DEPENDS ON THIS PATH: `#[derive(PartialEq)]` is documented in rparser.inc as lowering onto the shared record comparison, so this is a live wrong-answer path for Rust and not a Pascal edge case. 2026-09-07: the fix SHAPE is now measured, not open -- a byte-wise/memcmp compare is WRONG because pxx leaves record padding undefined (field-equal records differ in exactly their padding bytes on all five targets, 7 of 16 and 3 of 12, with a zeroed control at 0), so the compare must be FIELD-WISE. That also removes the stated reason this was a ticket rather than a fix: a field-wise expansion during IR lowering is one site and zero backends."
---

# Record equality compares one machine word

## Measured 2026-09-06, compiler sha256 `9e7426acb3c5`

`type TR = record x, y: Int64; end;` — `a.x=1, a.y=2` against four values of `b`:

| b | correct | x86-64 | aarch64 | arm32 | riscv32 | i386 |
| --- | --- | --- | --- | --- | --- | --- |
| `1, 2` identical | TRUE | TRUE | TRUE | TRUE | TRUE | **FALSE** |
| `1, 999` first same, last differs | FALSE | **TRUE** | **TRUE** | **TRUE** | **TRUE** | FALSE |
| `9, 2` first differs | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |
| `9, 9` both differ | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |

Rows 1, 3 and 4 are right **by accident** on the four working targets: a
first-word compare and a correct compare agree on all three. Only row 2
separates them, and it is the wrong direction — a spurious TRUE.

**Two targets could not have found this with an equal-records probe, and I
nearly did exactly that.** My first reading used `b := a` only, where a
first-word compare and a real one both say TRUE, and it scored aarch64/arm32/
riscv32 as OK. The probe whose right answer differs from the failure answer is
row 2, and it is the only row that measures anything.

## The mechanism, and it is deliberate as far as it goes

`ir.inc` refuses arithmetic on record operands and refuses ORDERING them, and
its comment says outright that `=`/`<>` stay exempt because *"a method-pointer
compare is a legitimate record `=`"*. So equality falls through to the scalar
`IR_BINOP`, which compares one machine word. That is correct for `TMethod`
(8 bytes on 32-bit) and wrong for every larger record. On i386 a record over 8
bytes is not in a register at all, so the fallthrough compares something that
never matches — which is why i386 answers FALSE even for a copy.

Boundary measured: **correct at `SizeOf <= 8`, wrong above it**, and it is
about the size, not the member types — `record x, y, z: Integer` (12 bytes) is
wrong on i386 too.

## Why this is not "we accept what FPC rejects, so it is not a defect"

FPC refuses the construct outright: `Operator is not overloaded: "TR" = "TR"`.
Accepting more than FPC is not a defect. **Accepting it and returning a wrong
value is**, and the wrong value here is a spurious TRUE with no diagnostic.

And the Pascal spelling is not the important consumer. **`rparser.inc:1455`
records that `#[derive(PartialEq)]` needs no code because *"the shared record
comparison"* already does it**, and `test/test_rust_derive.rs` asserts
`a == b`. Both of that test's rows pass on x86-64 for the wrong reason — its
unequal pair differs in the FIRST field, so a first-word compare gets it right.
**The test cannot see the bug it is nearest to.**

## A BYTE-WISE COMPARE IS NOT A CORRECT IMPLEMENTATION — measured 2026-09-07

One of the two options below is now ruled out on evidence. **Record padding is
not defined in pxx**, so a `memcmp`-shaped compare answers NOT EQUAL for two
records whose every field is equal.

`type TR = record b: Byte; y: Int64; end;` — `a` and `c` are LOCALS in a frame a
previous call filled with a pattern; both get `b := 1; y := 2` by field
assignment, then the bytes are compared through a `^Byte` walk:

| target | SizeOf | padding bytes | dirty frame | zeroed control |
| --- | --- | --- | --- | --- |
| x86-64 | 16 | 7 | **7 differ** | 0 differ |
| i386 | 12 | 3 | **3 differ** | 0 differ |
| aarch64 | 16 | 7 | **7 differ** | 0 differ |
| arm32 | 16 | 7 | **7 differ** | 0 differ |
| riscv32 | 16 | 7 | **7 differ** | 0 differ |

**The differing count equals the padding size EXACTLY on every target**, and no
field byte ever differs — so the walk is reading padding and nothing else. The
`zeroed` column is the control: the same records, byte-zeroed through the
pointer before the field assignments, report 0 on every target. A loop that
always answered nonzero would have failed that column.

**My first version of this probe could not have found it.** It put `a` and `c`
in the program's own `var` block, so both live in `.bss`, both padding regions
are zero by construction, and it printed `bytes differing=0` on all four targets
I ran — the expected value and the do-nothing value were the same number. The
frame has to be dirtied by a routine that has already returned for the question
to have two possible answers.

Note the asymmetry that makes this easy to miss: `c := a` goes through
`IR_COPY_REC`, which copies `RecSize` bytes INCLUDING padding, so a
copy-constructed record IS byte-identical to its source. A byte compare is
therefore correct for exactly the case everyone writes first, and wrong for two
records built the same way independently.

**So the implementation must be FIELD-WISE**, or byte-wise only for records the
layout tables show have no padding at all (which is a second mechanism serving
one concept, and the layout tables would have to answer recursively).

### And this narrows the fork's cost, which was the reason it was a ticket

"It is six backends" was the stated reason not to just do it. A field-wise
compare is **one site and zero backends**: expanded during IR lowering into
per-field scalar comparisons AND-ed together, it emits only `IR_LOAD_MEM` /
`IR_BINOP` nodes that every backend already handles, and it routes a managed
field (`AnsiString`) to the string compare for free. `IR_COPY_REC` exists with
no `IR_CMP_REC` mirror — but the mirror does not need to be an IR op.

Open questions the implementation still has to answer, none of them per-backend:
nested records and static arrays (recurse), variant records (`case` parts
overlap, so a field-wise walk compares bytes twice under different names), and
operands that are not lvalues (a function returning a record — `IRLowerAddress`
must have somewhere to point).

## The fork, which is why this is a ticket and not a fix

Two answers, and they are not the same size of change:

- **Implement it** — a byte-wise compare per backend, or one shared routine the
  way `PXXMemMove` already is, with the `TMethod` case falling out for free.
- **Refuse it**, matching the ordering arm one line above, with an exemption
  for method-pointer records.

**Refusing would break the Rust frontend today**, which is the fact that decides
it is not a quick call: `derive(PartialEq)` has no other implementation. Prefer
implementing; recorded here rather than chosen, because it is six backends.

## Acceptance

**Row 2 is the row.** Same first field, different last field, expected FALSE,
on every target — a relation with no per-target constant. It must go RED on
today's compiler on all five; taken above, so the reading exists before the fix.
Add an equal-records row beside it as the control that the fix did not simply
invert the answer, and a `TMethod`-shaped 8-byte row so the case the
fallthrough was protecting stays covered.

## Fixed 2026-09-07 — field-wise, in one place, zero backends

`ir.inc`'s BINOP lowering grew an arm for `=`/`<>` over two lvalue record
operands of the same record id: the two addresses are parked in scratch pointer
symbols, then the record's fields are expanded into
`(a.f1 = b.f1) and (a.f2 = b.f2) and ...`, recursing into nested record members
with the offset carried down. Three helpers beside it:
`RecCmpScalarKindOK` (the field-kind allowlist), `IRRecordIsFieldwiseComparable`
(the decide pass) and `IRRecFieldwiseEqChain` (the emitter).

**No backend changed.** The expansion emits `IR_FIELD` / `IR_LOAD_MEM` /
`IR_BINOP`, all of which every backend has always handled — which is what turned
"it is six backends" into one arm.

**The addresses are parked, not re-lowered per field.** A value node referenced
by two parents is emitted by BOTH, side effects included, so
`arr[F()] = b` would otherwise call `F` once per member. Same mechanism
`IRKindIsStatement`'s comment records costing us `IR_ATOMIC` and
`IR_VIRTUAL_CALL`.

### Measured, on the compiler built from this change

The ticket's own table, all four rows, all five targets — 40 of 40 cells
correct, i386 included. Then the wider shapes: a nested record (differing in
the inner member, in the tail, and in the head), a record with an `AnsiString`
member (two independently built heap strings with equal content compare EQUAL,
and a one-character difference in the LAST character compares unequal — so it
is content and not handle, and it is not a first-word compare), and a record of
`Double` + `Single` differing only in the `Single`. All correct on x86-64, i386,
aarch64, arm32 and riscv32.

**Positive control, taken against the pin v407 binary** (`095ef4811a5b`), which
predates the change: it fails 6 rows on x86-64/aarch64/arm32/riscv32 and 5 on
i386. `test_rust_derive.rs`'s new `tail` row reads `tail true false` there and
`tail false true` here — `derive(PartialEq)` was the live wrong-answer path and
now is not.

**Managed-string members neither leak nor over-release.** 300000 comparisons of
a record with an `AnsiString` member: the alloc census moves not at all
(`allocs=1 frees=0` before and after the loop), and under `-dPXX_HEAP_DEBUG`
both strings still read back intact afterwards. An `IR_LOAD_MEM` of a field is a
borrow, so `IRNodeOwnsManagedStr` answers False and the backends' string compare
emits no release for it.

### The residual, which is enumerated and not "probably fine"

`IRRecordIsFieldwiseComparable` refuses — and a refusal falls back to the OLD
one-word compare, never to an error, so it preserves a wrong answer and never
creates one:

- an **array** member, fixed or dynamic
- a **bit-field** member (C)
- a member of kind `tyString`/frozen, `tyExtended`, `tySet`, `tyVariant`,
  `tyPromoInt32/64`, `tyAuto`, `tyUnknown`
- **any record whose two fields OVERLAP** — a variant record's `case` parts, or
  a C union. That test falls out of the offsets rather than needing a
  variant-part column, so it covers the C frontend's unions for free. It is not
  merely redundancy being avoided: `record case Boolean of 0: (s: AnsiString);
  1: (n: Int64) end` would compare the same eight bytes once as a heap handle,
  dereferencing whatever the `Int64` arm stored, and once as an integer — a
  segfault reachable from a correct-looking program.
- a record with **no fields**, which has no honest answer

The array case is the one worth doing next and it is the largest remaining
population; it needs an element stride and a decision about the unroll cap.
Filed as `bug-a-record-equality-still-compares-one-word-when-a-member-is-an-array`
rather than left in this one's body.

### The method-pointer case, checked against the oracle and NOT a defect

The exemption this arm replaced was justified as *"a method-pointer compare is a
legitimate record `=`"*, so the obvious worry was that field-wise expansion
changes it. It does not, for two reasons worth writing down so nobody re-derives
them:

A `procedure(…) of object` variable is a PROCVAR, not `tyRecord`, so it never
reaches the new arm at all — measured identical on x86-64, i386, aarch64, arm32
and riscv32 before and after, and identical to pin v407.

And the answer it gives is CORRECT. Two method pointers bound to the same method
of DIFFERENT instances compare EQUAL — which looks wrong, and fpc 3.2.2 answers
exactly the same on the same source. Procvar `=` compares the code pointer only;
the instance half is reached through `TMethod(m).Data`. `SizeOf(TNotify)` is
`2 * SizeOf(Pointer)` on every target, so the storage is there and the operator
deliberately does not look at it. **I had written "want F" in the probe and the
oracle is what stopped a wrong ticket** — the probe's own premise (the two
instances are distinct) was asserted in the same run, so the reading is not a
constructor returning one object twice.

### Which frontends reach the arm today

Pascal and Rust. Measured, not assumed: NilPy has no record-value `==` spelling
(`a == b` on two instances is a class comparison, and a struct-shaped compare is
written field by field), and the Zig skeleton compiles `a == b` over two structs
to a body with nothing in it — `procs=2`, no `@import`, so it is not a consumer
of this path yet either. The arm is shared and the other frontends inherit it
the moment they grow the spelling; nothing about it is Pascal-specific.

### Gate

`test-record-equality-cross-target` — five targets, one expected block,
`test/record_equality_rows.pas` + `.expected`. Enrolled in testmgr.py's `full`
tier, along with two sibling cross-target gates that were in no tier at all
(`bug-t-25-of-56-make-test-targets-are-reachable-from-no-tier`).

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
