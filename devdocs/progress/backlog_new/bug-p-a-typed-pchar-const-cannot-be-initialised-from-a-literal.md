---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`const GP: PChar = '-'` COMPILES and segfaults (the ordinal is stored as the pointer); `const GP: PChar = '--'` is \"unexpected token\"; `const A: array[0..1] of PChar = ('-', '--')` is \"too many array constant elements\". A typed PChar const initialised from a literal is unimplemented in all three shapes, and the one-character shape fails SILENTLY. FPC gives the address of the NUL-terminated data."
status: backlog
owner: unassigned
---

# A typed `PChar` const cannot be initialised from a string literal

Found 2026-08-26 by Track P while fixing
`bug-single-char-literal-as-pchar-argument-segfaults`. That fix covered every
*expression* context a one-char literal reaches (argument, method argument,
overload, assignment, comparison); the typed-CONST DECLARATION is a different
machinery (`PendingInit*`) and was not touched.

## Repro — three shapes, all broken, one of them silently

```pascal
program d;
const GP: PChar = '-';
begin Writeln(GP); end.
```

| shape | FPC 3.2.2 | pxx (HEAD, 2026-08-26) |
| --- | --- | --- |
| `const GP: PChar = '-'` | prints `-` | **compiles, then SEGFAULTS** |
| `const GP: PChar = '--'` | prints `--` | `error: unexpected token` |
| `const A: array[0..1] of PChar = ('-', '--')` | prints `-` | `error: too many array constant elements` |
| `const A: array[0..1] of PChar = ('--', '--')` | prints `--` | same error |

The one-character row is the dangerous one and the reason this is prio 70
rather than 55: it is accepted, because the literal folds to its ORDINAL and
an ordinal is a perfectly good initialiser for a pointer-sized slot. The
program then dereferences address 45. The two-character rows at least refuse.

## Mechanism (partly measured)

`compiler/pasparser_decl.inc`, the scalar typed-const arm (~2288, "SCALAR typed
const: `const P: Pointer = @Something`"): its own comment says *"The string arm
cannot fire here — a string-typed const is handled well above this point"*, so
a pointer-typed const falls to `TryParseInitValForm` / `ParseInitValTk`, which
know `@proc` / `@var` / an ordinal and nothing else. A one-char literal IS an
ordinal there; a multi-char literal is not a token either of them expects.

The array arm is `compiler/pasparser_decl.inc:2002`/`2012` — the flat element
tally counts differently from what the parser then consumes for a literal
element.

A fix needs a new `PendingInit` kind that emits a data-section relocation to
the interned literal's character data (the `+8` past the length prefix), which
is the same address the argument path now passes.

## Sibling check while fixing

The parameter-default form is filed separately as
`bug-p-a-string-literal-is-refused-as-a-pchar-parameter-default` — same
"a literal must become a pointer to its data" rule, a third machinery.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + all four rows above
matching FPC. Add them to `test/test_char_literal_to_pchar_param.pas`, which
already asserts the expression side of the family.
