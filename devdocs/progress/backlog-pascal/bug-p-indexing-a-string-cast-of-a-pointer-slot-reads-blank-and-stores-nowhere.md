---
slug: bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere
title: "Indexing a string cast of a Pointer slot reads a blank char, stores nowhere, and does not parse in the built-in spelling"
track: P
prio: 45
type: bug
status: backlog
found: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "`type t = AnsiString; var r: Pointer; t(r) := 'abcde'; t(r)[2]` reads a BLANK character where fpc 3.2.2 -Mdelphi reads `b`, and `t(r)[2] := 'X'` stores NOWHERE -- both silent, no diagnostic. The BUILT-IN spelling of the same line does not parse: `AnsiString(r)[3] := 'X'` is `expected ':=' before '['`. Three faces, one construct: a string cast over a Pointer slot with a subscript. Found while closing bug-p-setlength-over-a-string-cast-of-a-pointer-slot-has-no-lowering, whose test had to drop a row because of it; the value shape (assign, read, Length, SetLength, Copy) is now correct through both spellings and only the INDEXED shape is not. NOT the same defect as bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index, which is about a string VARIABLE operand and is fixed."
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
