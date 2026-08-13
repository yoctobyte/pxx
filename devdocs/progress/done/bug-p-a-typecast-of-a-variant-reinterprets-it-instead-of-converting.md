---
track: P
prio: 62
type: bug
blocked-by: []
summary: "`Int64(v)` on a Variant answers 1 (the variant's TAG word) where FPC answers 9, and `Double(v)` SEGFAULTS. FPC/Delphi treat a typecast of a variant as a CONVERSION; pxx treats it as a reinterpret of the variant RECORD. Silent wrong value on the integer side, crash on the float side."
status: done
owner: agent-apn
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

## Progress (2026-08-13)

**Fixed.** Normalised onto the assignment, per the shape the ticket names:
`VariantCastToTemp` (parser.inc, beside `PromoDemoteToInt64`) rewrites a cast
of a variant operand into a hidden temp of the CAST's type plus a store —
`ir.inc`'s `AN_ASSIGN` arm already emits the `VariantTo*` / `pyvar_to_*` unbox
there. One mechanism, every spelling, all six backends, no new IR op.

The cast sites are FIVE, not one, and the ticket's own "grep the siblings"
warning was the load-bearing part:

- `tkInteger_T`/`tkLongWord_T` — Byte / LongWord (AN_PTR_CAST) and the
  Integer/LongInt value-pun (AN_CALL)
- `tkChar_T`/`tkBoolean_T` — the Char/Boolean puns
- `tkSingle_T`/`tkDouble_T`/`tkExtended_T` — the temp desugar
- `tkString_T` — was a hard `Error('String(): operand must be Char or string')`
- the identifier-named builtin cast (`AnsiString(v)`, `Cardinal(v)`, enums)
- **and the separate identifier-named ORDINAL cast at parser.inc:~12250**,
  which is where `Int64(v)` / `QWord(v)` / `NativeInt(v)` actually land. After
  the other five were fixed, `Int64(v)` — the ticket's headline symptom — still
  answered 1. That site's own comment already documents this exact two-sites
  trap for `PromoDemoteToInt64`; it now documents it for the variant cast too.

### A second bug fell out of the float arm

`Single(expr)` / `Double(expr)` desugar to `op := AllocVar('', LastExprTk)` —
but `ParseExpr` OVERWRITES `LastExprTk` with the OPERAND's kind, so the
"conversion" allocated a temp of the SOURCE type and no conversion happened:

- `WriteLn(Single(d):0:10)` with d=3.7 printed `3.7000000000` (unnarrowed);
  FPC prints `3.7000000480`. Invisible whenever the result was assigned to a
  Single, because the STORE narrowed it — the classic "one arm of a double
  case stays broken".
- for a variant operand it built a VARIANT temp, so `Double(v)` stored the
  16-byte record through an 8-byte value slot: that was the SEGFAULT.

Capturing the kind before `ParseExpr` fixes both.

### Verified

`test/test_variant_typecast.pas` (new, wired into `make test`): all 14 cast
spellings over a variant holding an int, a float, a bool and a string, diffed
against an FPC build of the same file. Every row matches except two the file
flags in-place, both of which are the CONVERSION's own FPC parity and reproduce
identically through `i := v` —
[[bug-p-variant-to-int-and-char-conversion-diverges-from-fpc]] (filed):
boolean→Int64 gives 1 where FPC gives -1, and Char(65) gives 'A' where FPC
renders '65' and takes '6'.

`NativeInt(v)` is left out of the oracle file: FPC REFUSES it ("Illegal type
conversion"), pxx's lax dialect converts it. Nothing to diff.

Not touched: `Pointer(v)` stays a reinterpret (the record's address is the only
sensible reading), and `WideChar(v)` converts and then keeps its -3 marker by
wrapping the converted temp rather than exiting the arm.

**Gate:** `tools/gate.sh quick` GREEN (self-host fixedpoint + testmgr quick +
FPC seed canary), `make test-nilpy` GREEN — the nilpy suite because this
changes a VARIANT lowering that pylib's Pascal sources compile through.

## Log
- 2026-08-13 — resolved, commit 24204e10d.
