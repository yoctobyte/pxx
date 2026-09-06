---
slug: bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere
title: "Indexing a string cast of a Pointer slot reads a blank char, stores nowhere, and does not parse in the built-in spelling"
track: P
prio: 45
type: bug
status: done
found: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
summary: "RESOLVED 2026-09-06. All three faces green and matching fpc 3.2.2 byte for byte (test_indexing_a_string_cast_of_a_pointer_slot, 10 rows, wired). ONE cause and two untaught spellings, which is NOT what this ticket predicted: the IR's typed-pointer-cast index arm (compiler/ir.inc) read the ALIAS INDEX off the cast node, and a string cast carries -1 -- the same marker the PChar ADAPTER carries -- so a string cast was indexed by the adapter's rule, 0-BASED with a char element. The tk on the cast node is the discriminator, never the alias index. The blank read was a second, earlier gap: over a POINTER operand the expression arm built no cast node at all, only a retag, so there was nothing for the lowering to read. Both built-in spellings (`AnsiString(r)[2]`, `String(r)[2]`) simply never reached the shared selector walk; the indexed STORE is now one call to FinishCastAsLValueStore for both the alias and built-in spellings rather than a fifth arm. My own prediction that the rvalue loop was 'indexing the cast wrapper' was wrong -- the wrapper did not exist."
---

# Indexing a string cast of a `Pointer` slot: blank read, lost store, and one spelling that will not parse

## Measured 2026-09-06 against `fpc 3.2.2 -Mdelphi`

```pascal
type t = AnsiString;
var r: Pointer;
begin
  t(r) := 'abcde';
  WriteLn('A read idx : [', t(r)[2], ']');     { fpc: [b]      pxx: [ ]      }
  t(r)[2] := 'X';
  WriteLn('B after store : ', t(r));           { fpc: aXcde    pxx: abcde    }
  AnsiString(r)[3] := 'Z';                     { fpc: aXZde    pxx: won't parse }
end.
```

`pascal26: error: expected ':=' before '['` for the built-in spelling.

## Why it is its own ticket

It was found while closing
[[bug-p-setlength-over-a-string-cast-of-a-pointer-slot-has-no-lowering]], and it
is **not** that defect nor its parent's. As of that fix the VALUE shape of a
string cast over a pointer slot is correct through both spellings — store, read,
`Length`, `SetLength` (shrink and grow, with the handle written back), `Copy`.
Only the subscript is wrong, and it is wrong in three different ways at once,
which is the signature of three separate paths rather than one.

It is also **not**
`bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index` (closed): that
one is a string VARIABLE operand, and `TS(s)[2]` works today. The operand class
is the discriminator here exactly as it was for the value shape — which is the
third time on this construct that a "this works" claim turned out to be scoped
to the operand that happened to be tried.

## Where to start, and what NOT to assume

- The rvalue path is `pasparser_expr.inc`'s C4 arm, whose `strAliasIdx` flag
  routes `[` to the shared suffix loop. That loop reads the base kind off the
  node; for a POINTER operand the node is now an `AN_PTR_CAST` tagged with the
  string kind rather than the operand itself, so the loop may be indexing the
  cast wrapper.
- The lvalue path is `pasparser_stmt.inc`'s C4 store arm, which has a
  `tkLBrack` guard testing the OPERAND for a string
  (`bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index`). A pointer
  operand fails that test, exactly as it failed the whole-value one beside it
  until 2026-09-06.
- The built-in spelling not parsing at all means it never reaches either — the
  `ParseCastAsLValueStore` path takes `(`…`)` and then demands `:=`.

**Do not assume one fix covers the three.** One diagnostic across N sites is not
evidence of one defect, and here there are three different observables, which is
weaker evidence still. Establish where each gives up first.

## What a fix has to satisfy

1. `t(r)[2]` reads `b`; `t(r)[2] := 'X'` yields `aXcde`.
2. `AnsiString(r)[3] := 'Z'` compiles and does the same.
3. `TS(s)[2] := 'X'` over a string VARIABLE keeps working (it does today).
4. The value shape through a pointer slot keeps working — there is a wired test,
   `test_setlength_through_a_string_cast_of_a_pointer_slot`, whose row F exists
   because of this ticket and must stay green.

## RESOLVED 2026-09-06 — one discriminator, two untaught spellings

`test/test_indexing_a_string_cast_of_a_pointer_slot.{pas,expected}`, wired in the
`Makefile`. `.expected` is fpc 3.2.2's own output byte for byte; all ten rows
agree.

**THE CAUSE WAS NOT WHERE THIS TICKET POINTED, AND THE THREE OBSERVABLES WERE
NOT THREE DEFECTS — nor were they one.** They were one missing discriminator
plus two spellings that never reached the shared walk:

- **`compiler/ir.inc`, the typed-pointer-cast index arm.** It reads the alias
  index off the cast node and falls to a `< 0` branch meaning *the PChar
  adapter*: char element, byte stride, **0-based**. A string cast carries the
  same `-1` (the built-in-cast marker), so it took the adapter's rule and
  `t(r)[1]` answered the SECOND character. Three spellings of "no alias row"
  share one slot value; only the cast's **tk** tells them apart. A string cast
  now indexes as string DATA — 1-based off the handle for a managed string, off
  the length prefix for a frozen one.
- **`compiler/pasparser_expr.inc`, the C4 `strAliasIdx` arm.** Over a POINTER
  operand it retagged only the TK and built no `AN_PTR_CAST` at all, so the
  lowering above had nothing to read and the read came back blank. This is the
  same seam the value shape had, one operand class over: *"this part works"*
  scoped to the operand that was tried.
- **Both built-in spellings never reached the walk.** `AnsiString(r)[2]` (the
  identifier path) and `String(r)[2]` (the `tkString_T` keyword path, which by
  construction never reaches the identifier path) each exited with the subscript
  still in the token stream, so the enclosing expression reported `expected ')'
  before '['`. Third time this file has fixed one concept one spelling at a
  time.
- **The store is one call, not a fifth arm.** `FinishCastAsLValueStore` grew the
  indexed-string head, and the C4 pointer-operand arm's guard widened from
  `tkAssign` to `tkAssign or tkLBrack`. The four shapes here are one 2×2 —
  {whole value, indexed} × {string operand, pointer operand} — and the
  indexed/pointer cell was the empty one.

**Row I is the positive control and it is the only row that can catch this being
widened**: `PChar(s)[0]` must stay 0-based. A guard written as "not an alias
row" instead of "the tk is a string" passes every row in this file except that
one.

**Corrections to my own text above**, left in place rather than deleted:

- *"the loop may be indexing the cast wrapper"* — there was no wrapper. Over a
  pointer operand the arm built none.
- *"the built-in spelling ... never reaches either"* — true, and the remedy was
  not to route it to the statement path but to give both built-in spellings the
  same shared selector walk the alias spelling already had.
- The measured error for the built-in spelling is `expected ')' before '['` in
  expression position; the ticket recorded `expected ':=' before '['`, which is
  the statement-position face of the same absence.

Cross-frontend, per the shared-machinery rule (`ir.inc` serves every frontend):
C `((char*)p)[i]` read and store plus a literal subscript match gcc; NilPy
`s[1]`, a slice, `"a" * 3` and `*rest/**kw` match CPython.

`tools/gate.sh quick` run with the tree DIRTY (so the FPC seed canary ran, and
it PASSED). The gate's one RED is `pinned builds live lib/rtl` — the pinned
compiler cannot build `mimic_string` / `mimic_urllib_request`, which name
`pyvar_is_objtag` / `pyvar_is_inttag`, builtins added by `a627e019c` /
`5a900c598` in files this change does not touch. Pre-existing, and its own log
says the remedy is a pin.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1434c655b.
