# Anonymous (inline) record types — `var x: record ... end;`

- **Type:** feature (parser) — Track A
- **Status:** backlog
- **Opened:** 2026-07-01 (found incidentally while writing an oracle test —
  `test/test_asm_emit_x64.pas`/`test_asm_emit_386.pas` use the form for scratch
  fixup tables, FPC-only files, never self-hosted, so the gap went unnoticed)

## What's missing

Standard Pascal (going back to Wirth's original report / ISO 7185 — not a
modern Delphi addition; Turbo Pascal and FPC have always had it) allows a
`record ... end` type *literal* anywhere a type is expected, not just after
`type Name = `. Same rule that already lets `array[0..9] of Integer` appear
directly in a `var` section without a named type — records never got the
equivalent.

```pascal
var
  X: record CodePos, DataOff: Integer; end;   { legal FPC/Delphi, rejected by pxx }
```

pxx fails with `Expected: begin, but got: end`, pointing at the record's `end`
— reproduces even stripped to one field, no array wrapper:

```pascal
var X: record CodePos: Integer; end;   { same error }
```

Neither wrapping in `array[..] of` nor the `A, B: Integer` comma-field
shorthand is the cause — it's the bare anonymous `record...end` itself pxx's
parser can't handle in a `var` type position.

## Root cause (traced this session)

`ParseVarSection` (`compiler/parser.inc:9393`) dispatches the type after `:`
on `CurTok.Kind`:
- named array-type identifier → `compiler/parser.inc:9421-9447`
- `tkArray` → full anonymous-array handling, `9448-9582`
- everything else → a generic one-token-at-a-time skip loop
  (`9583-9592`) that keeps calling `ParseTypeKind` until it sees
  `;`/`=`/`begin`/`var`/`const`/`type`/`procedure`/`function`/EOF.

There is **no `tkRecord` branch** in that dispatch, nor in `ParseTypeKind`
itself (`compiler/parser.inc:9156`, `case CurTok.Kind of` block
`9169-9388` — no `tkRecord` case; named records only resolve through the
identifier/else path via `IsRecordType`, line `9341`).

Concretely: the skip-loop calls `ParseTypeKind` on `record`, then on `,`, then
`DataOff`, then `:`, then `Integer` — each falls into an unrelated
scalar/enum-fallback branch and blindly consumes one token
(`ParseTypeKind`'s trailing `Next`, line `9390`). It stops at the `;` right
after `Integer` (in the stop-set) — **never consuming the record's `end`**.
`ParseVarSection`'s `while CurTok.Kind = tkIdent` loop (`9405`) then exits
because `CurTok` is `tkEnd`, and the enclosing block parser reports "Expected:
begin, but got: end" at that leftover token. Not a record-specific bug so much
as "nothing ever told the skip-loop a record type exists."

## Existing precedent to follow

Named `record`/`packed record` parsing is not a standalone routine — it's
inlined directly in `ParseTypeSection` (`compiler/parser.inc:10098`), the
`(CurTok.Kind = tkPacked) or (CurTok.Kind = tkRecord)` branch at `10943`. It
calls `AddUClass(tnOff, tnLen)` (`10953`) to register the record in the
`UCls*` tables (name = the `type` alias being declared), then parses fields
inline — a ~280-line loop (`10956-11227`, comma-field-lists, nested/dynamic
array fields, `case`/variant sections) using ~15 locals shared with the
enclosing procedure — closing at `Expect(tkEnd, 'end')` (`11227`).

The right precedent for an *unnamed* record is `EnsureMethodPtrRec`
(`compiler/symtab.inc:501-515`): it calls `AddUClass(0, 0)` — offset/len `0`
meaning "no name" — to mint an unnamed `UCls` entry, sets its layout directly,
and returns `REC_UCLASS_BASE + ci`. Anonymous arrays (`AllocArray`/
`AllocDynArray`, `compiler/symtab.inc:1844`/`1939`) and anonymous sets
(`ParseTypeKind`'s `tySet` case, `9244-9268`) don't use a type-table row at
all — they stash shape directly on the variable's `Sym*` fields — but a
record's field layout is too rich for that shortcut; the unnamed-`UCls`-row
approach is the fit here.

## Scope

1. Extract the field-parsing loop (`10956-11227`) into a helper parameterized
   by the target `ci` (or duplicate a reduced, non-variant subset first if
   that's the smaller/safer first cut — plain fields only, defer `case`
   variant sections in an anonymous record to a follow-up if they add real
   risk).
2. Add a `tkRecord`/`tkPacked` case to `ParseTypeKind` (mirrors how `tkCaret`/
   `tkSet` already fully self-consume before returning): `ci := AddUClass(0,
   0); UClsIsRecord[ci] := True;` → call the extracted helper → `Expect(tkEnd,
   'end')` → `LastTypeRecId := REC_UCLASS_BASE + ci; Result := tyRecord`.
3. This one addition should fix `var` decls for free (they already route
   through the generic skip-loop → `ParseTypeKind`), plus function
   params/array-element-types/return-types that also call `ParseTypeKind` —
   no separate wiring needed per call site.

Front-end only; no IR/codegen/backend changes expected.

## Risk

Moderate, not large: no new IR/codegen, but the field-parsing block being
extracted is feature-rich (variant/`case` records, nested/dynamic-array
fields, packed alignment) and deeply embedded in `ParseTypeSection`'s local
scope — the extraction itself is the real work, not the one-line dispatch
addition.

## Acceptance

- `var x: record a, b: Integer; end;` parses, fields addressable
  (`x.a := 1;`), `SizeOf(x)` correct.
- Works as a function param type, array element type
  (`array[0..3] of record a: Integer; end;`), and function return type.
- Self-host byte-identical; `make test` green. No change to named-record
  parsing or existing test output.

## Log
- 2026-07-01 — Opened. Found while adding oracle-test coverage during the
  ongoing `ir_codegen.inc` → `EmitAsmX64` migration
  ([[feature-asm-structured-ir-library]]); `test_asm_emit_x64.pas`/
  `test_asm_emit_386.pas` (FPC-only harnesses) use the anonymous-record form
  for scratch fixup tables, which is why it was never hit by self-host.

## Resolution — 2026-07-02, landed (v140)

Implemented per the ticket's own plan:

1. **Extraction**: the ~270-line field-parsing loop moved verbatim out of
   ParseTypeSection into `ParseRecordFields(ci, isPackedRecord)` (own locals,
   forward-declared; named-record branch now calls it). Extraction verified
   faithful — the intermediate build was byte-identical before the new case
   was exercised.
2. **ParseTypeKind gains a tkRecord/tkPacked case**: mint an unnamed UCls row
   (`AddUClass(0,0)`, the EnsureMethodPtrRec precedent), parse fields with the
   shared helper, `LastTypeRecId := REC_UCLASS_BASE + ci`, return tyRecord.
   Var decls / array elements / params / nested fields all route through
   ParseTypeKind, so they work with no per-site wiring (ticket's prediction
   held). `packed record` accepted; `packed` + anything else errors (was
   never routed here before).
3. **Real bug found by the nested case — AddUField window relocation**: UCls
   field storage is a contiguous `[UClsFBase, +UClsFCount)` window over
   global UFld* arrays. A NESTED anonymous record parsed mid-record registers
   its fields between two of the outer's, corrupting the outer's window
   (repro: `p: record n: Integer; sub: record q: Integer; end; end` — p.n
   read back p.sub.q's value). AddUField now relocates a class's
   fields-so-far to the tail and re-bases when its window is strictly behind
   the tail. Guard subtlety (caught by test/cglobal_struct_array_fnptr_cast_
   b98.c segfaulting): the C struct parser re-anchors UClsFBase to the tail
   with a stale UClsFCount before re-appending buffered fields — a window
   extending PAST the tail is that manual-rebase state and must be left
   alone (`<` not `<>` in the trigger).

Extras that fell out: packed anon records (SizeOf pinned), case/variant
sections (union overlay pinned), managed-string fields (ARC on scope exit,
1000-iteration churn in the test; RSS-flat in a 100k manual run), var-param
anon records (a pxx extension — real FPC rejects the form in parameter
lists; kept since the ticket's acceptance asked for it).

Gate: test/test_anonymous_record.pas (8 cases) in make test; full suite
green; self-host byte-identical; pinned v140.
