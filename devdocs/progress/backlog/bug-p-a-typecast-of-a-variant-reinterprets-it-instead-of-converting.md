---
track: P
prio: 62
type: bug
blocked-by: []
summary: "`Int64(v)` on a Variant answers 1 (the variant's TAG word) where FPC answers 9, and `Double(v)` SEGFAULTS. FPC/Delphi treat a typecast of a variant as a CONVERSION; pxx treats it as a reinterpret of the variant RECORD. Silent wrong value on the integer side, crash on the float side."
---

# A typecast of a Variant reinterprets the record instead of converting

- **Type:** bug (silent wrong value, then a crash) — **Track P** (Pascal
  dialect semantics; the cast lowering is shared parser/IR ground, so the fix
  may land as Track A)
- **Found:** 2026-08-12, while writing pylib runtime code for
  [[bug-nilpy-class-attribute-through-a-class-reference-reads-garbage]] — a
  `Int64(dict.fetch(k))` handed back a STACK ADDRESS, and the same spelling one
  line over wrote the tag word `1` into a program's class attribute where it
  had assigned 9.

```pascal
program vcast;
{$mode objfpc}
uses variants;
var v: Variant; i: Int64; d: Double;
begin
  v := 9;
  i := Int64(v);   WriteLn('int64cast=', i);
  v := 2.5;
  d := Double(v);  WriteLn('dblcast=', d:0:2);
end.
```

| | FPC 3.x | pxx (HEAD 2026-08-12) |
| --- | --- | --- |
| `Int64(v)` with `v = 9` | `9` | **`1`** |
| `Double(v)` with `v = 2.5` | `2.50` | **SIGSEGV** |

FPC and Delphi define a typecast of a variant as the variant CONVERSION (the
same one `i := v` performs). pxx lowers it as an ordinary hard cast of the
16-byte variant RECORD, so the value read is the tag word — or, for the float
kinds, whatever reinterpreting those bytes as an address leads to.

`1` is the worst available answer: it is a plausible integer, it is what a
VT_* tag happens to be for several kinds, and every arm of a kind-dispatch
chain written with `Int64(v)` / `Integer(v)` / `Byte(v)` gets it.

## Why it matters beyond the one spelling

The assignment form (`i := v`) is correct, so the two spellings of the same
intent disagree — which is exactly the double-case shape
`devdocs/dev/normalise-dont-special-case.md` warns about. Anyone porting FPC
code (the compat lane's whole business) writes the cast form.

## Where to look

The cast is built in the shared type-cast path in `parser.inc` (the
`TypeName(expr)` conversion arm) and lowered in `ir*.inc`. The fix is to
recognise a VARIANT operand there and emit the variant→scalar conversion the
assignment path already emits, rather than a reinterpretation. Grep for the
sibling spellings before closing: `Integer(v)`, `Boolean(v)`, `Char(v)`,
`Single(v)`, `NativeInt(v)` — a fix on the Int64 arm alone leaves the rest as
they are.

## Gate

`make test` + self-host fixedpoint; a `.pas` test diffed against FPC covering
Int64/Integer/Byte/Boolean/Char/Single/Double casts of a variant holding an
int, a float, a bool and a string.
