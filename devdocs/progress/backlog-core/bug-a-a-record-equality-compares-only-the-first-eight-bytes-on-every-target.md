---
track: A
prio: 75
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [records, equality, cross-target, silent-wrong, rust]
blocked-by: []
summary: "`a = b` on a plain record compares ONLY THE FIRST 8 BYTES on x86-64, aarch64, arm32 and riscv32, and answers FALSE unconditionally on i386. Two records with the same first field and a different last field compare EQUAL -- a wrong TRUE, silently, on four targets; on i386 a record is never equal to a byte-identical copy of itself. Measured 2026-09-06 with a 12-line Pascal program, confirmed through an `if` as well as a WriteLn argument. `ir.inc`'s BINOP lowering leaves `=`/`<>` on records to fall through to the scalar IR_BINOP DELIBERATELY -- its comment says method-pointer compares are legitimate record `=` -- so no general record comparison was ever emitted and the fallthrough compares one machine word. FPC REFUSES the construct (`Operator is not overloaded: \"TR\" = \"TR\"`), so the Pascal side is us accepting more than FPC AND answering wrong, which is a defect regardless. THE RUST FRONTEND DEPENDS ON THIS PATH: `#[derive(PartialEq)]` is documented in rparser.inc as lowering onto the shared record comparison, so this is a live wrong-answer path for Rust and not a Pascal edge case."
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
