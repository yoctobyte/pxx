# Implementation Architecture

Durable internal-architecture reference: include chain, generic machinery,
library resolution, hard-won gotchas, class/method layout, dialect switches,
and operator overloading. For dated, point-in-time state see
[`COMPATIBILITY.md`](../COMPATIBILITY.md) (feature inventory),
[`todo.md`](todo.md) (remaining work), and
[`ir-handover.md`](ir-handover.md) (IR backend status). The 2026-05-28
session snapshot this file was split from lives in
[`historic/handover-2026-05-28.md`](historic/handover-2026-05-28.md).

## Architecture

- `compiler/compiler.pas` — main entry, includes all `.inc` files
- Include chain: `defs.inc` → `lexer.inc` → `clexer.inc` → `blexer.inc` →
  `emit.inc` → `symtab.inc` → `exception_emit.inc` → `asmenc.inc` →
  `parser.inc` → `ir.inc` → `ir_codegen.inc` → `cparser.inc` → `bparser.inc` →
  `elfwriter.inc` → `rtti_emit.inc` → `resources_emit.inc` → `cpreproc.inc`
- Pipeline: source → tokens → AST → linear IR → x86-64 bytes → ELF write
- No linker, no stdlib, no runtime
- Static programs: one load segment, no dynamic section
- Dynamic programs (any external call): emit PT_INTERP, PT_DYNAMIC, DT_NEEDED, GOT,
  plt-style indirect calls

The active backend is the IR pipeline (`ir.inc` + `ir_codegen.inc`), and the
compiler bootstraps through it. The obsolete direct AST→x86-64 emitter was
archived as `historic/direct-codegen-legacy.inc` on 2026-05-31. See
[`ir-handover.md`](ir-handover.md).

## Token Stream / Generic Machinery

- `TemplateTokens`: flat `TRawToken` array; templates (classes and functions) stored by
  index range `[TokStart, TokStart+TokCount)`.
- `SpecializeStream(...)`: substitutes template parameters through global
  `SpecializeTokens` scratch storage, inserts at `TokPos`, and shifts tokens right.
- `InsertTokens(insertPos, src, count)`: core insert primitive; TokPos unchanged.
- `ParseGenericFunctionDef`: `generic function/procedure Name<T>` — prepends synthetic
  `tkFunction`/`tkProcedure` + `tkIdent` tokens, buffers rest into TemplateTokens.
- `ParseTopLevelSpecialize`: does NOT consume `;` before inserting — insert while
  CurTok=`;` so after `ParseSubroutine` returns, CurTok lands on next top-level token.

## Header / Library Resolution

`uses name;` searches: local dir, `compiler/`, `/usr/include/`. `.h` → external
prototype + dynamic resolve. `ctype` hardcoded → `libc.so.6`. Other headers default
`lib<name>.so`.

## Key Gotchas

- **Append new token kinds**: inserting token kinds in the existing enum changes
  ordinals and can destabilize bootstrapped code.
- **`ASTIVal` must be `Int64`** — `Integer` truncates $FFFFFFFF in shr codegen.
- **`shr` binop**: save `Tokens[TokPos-1].SOffset/SLen` BEFORE `Next`, then set on AST node.
- **String data layout**: `Strs[i].Offset` = 8-byte length prefix; actual bytes at `+8`.
- **`UnitContent` buffer**: must be global — local `AnsiString` can't hold ~11KB headers.
- **`CPExpandFunction` args**: depth-indexed fixed storage, not local open arrays
  (self-hosted stack limitation).
- **Single-char string literals**: `'x'` → `AN_INT_LIT` with `ASTTk=Ord(tyChar)`.
  The IR emitter's string-vs-char path handles comparisons like `field = 'x'`.
- **String `+` concatenation**: emitter generates 272-byte stack temp buffer; correct
  type propagation across variables, literals, and chars.
- **Nested/Recursive Lexer Stack Fix**: `SavedLexSource` is a 1 MB global in `defs.inc`.
  Local `AnsiString` for saved source caused stack overflow (256-byte `LOCAL_STR_CAP` limit).
- **New record types require FPC bootstrap**: `symtab.inc` hardcodes all record types.
  Adding one means the old seed doesn't know it, requiring `make bootstrap`. After
  bootstrap, self-hosting resumes at fixedpoint.
- **`ParseTopLevelSpecialize` semicolon**: do NOT call `Eat(tkSemicolon)` before
  `SpecializeStream`. Insert must happen while CurTok=`;`; otherwise CurTok after
  `ParseSubroutine` lands inside the next `specialize` statement.
- **Generic specialization scratch storage**: `SpecializeTokens` and
  `SpecializeTemplateName` are globals. A local temporary token array corrupted
  self-hosted generic specialization.
- **`REC_UCLASS_BASE` must exceed all hardcoded type IDs**: hardcoded types live in
  `symtab.inc`. If `REC_UCLASS_BASE` doesn't clear the max, user class 0 collides with
  a hardcoded record branch in `RecFieldOffset`/`RecFieldType`, every field offset
  returns 0, and all fields of a user class read/write offset 0 (last write wins).
  Rule: whenever a new hardcoded record type is added to `symtab.inc`, bump
  `REC_UCLASS_BASE` past the new max.
- **Self-evolution bootstrap rule**: evolve using self-hosted seed by default. FPC is
  recovery path only. Note any use of FPC bootstrap in `compiler/usernotes.md`.
- **Map File output**: uses shared `TokChars` buffer; `sysfchmod` with decimal `420`
  (chmod 644) for permissions.

## Class / Method Implementation Details

- `REC_UCLASS_BASE` — user classes start at this recId; must clear all hardcoded type
  IDs (see gotcha above).
- `REC_TMYCLASS` is a HARDCODED legacy class; `TMyClass` still routes to it via
  `IsRecordType`. All other user-defined classes use the dynamic UClass system.
- `ParseTypeSection` registers every `class` type via `AddUClass`/`AddUField`.
- Method implementations (`procedure ClassName.MethodName`) registered via `AddUMeth`
  from `ParseSubroutine` when `FindUClass(name) >= 0`.
- `Self` injected as implicit param 0 of type `tyClass`; `RecName` set to owner class
  recId so `Self.Field` resolves via `FindUField`.
- `.Create` detected in `ParseFactor`; maps to `GetMem(UClsSize_[ci])`.
- **RTTI (published)**: `rtti_emit.inc` emits our own blob layout (`RTTI_*` in
  `defs.inc`) for published fields/props/methods; `AddDataPtrFix` does data→data
  pointer relocation; name→RTTI registry reachable at runtime via the `__rttireg`
  intrinsic. Reflection RTL is `compiler/typinfo.pas`. See
  [`plan-rtti-streaming-lfm.md`](plan-rtti-streaming-lfm.md).

## Dialect / Compiler Switches

- `PXX` is predefined, `FPC` is not; named define conditionals nest; `-dNAME`,
  `-uNAME`, and `-Mobjfpc` are accepted.
- `strict_overload` (default off): `{$strict_overload on}` / `--strict-overload`
  requires explicit `overload` on overloaded procs.
- `--no-unhandled-handler` / `-fno-unhandled-handler`: suppresses the generic
  unhandled-exception diagnostic while preserving exit status 1.
- `generic_syntax` (default b1): b1=top-level `generic function`+`specialize as`,
  a=type-section style.

## Operator Overloading

Syntax:
```pascal
operator < (a, b: TWeight): Boolean;
begin Result := a.Value < b.Value; end;

operator + (a, b: TPoint): TPoint;
var r: TPoint;
begin r := TPoint.Create; r.X := a.X + b.X; r.Y := a.Y + b.Y; Result := r; end;
```

Implementation:
- `defs.inc`: 4 parallel arrays (`OvrlOpKind`, `OvrlTypeKind`, `OvrlRecId`, `OvrlProcIdx`)
  + `OvrlCount`. `MAX_OP_OVERLOADS=64`.
- `symtab.inc`: `RegisterOpOverload(opKind, typeKind, recId, procIdx)` and
  `FindOpOverload(opKind, typeKind, recId) → procIdx`.
- `parser.inc`: `ParseOperatorDef` — called from `ParseProgram` when `CurTok='operator'`.
  Lookahead inside `()` to find first `:` at depth=1, reads type name via
  `GetTokenStrFromRaw(SOffset, SLen)`. Injects `function __op__NN (` into token stream,
  calls `ParseSubroutine`, then `RegisterOpOverload`.
- `parser.inc`/`ParseSubroutine`: `ptypesRec[i] := LastTypeRecId` after `ParseTypeKind`;
  sets `Syms[idx].RecName := ptypesRec[i]` for class/record params so field lookups work.
- Binop handling: before all other binop handling, call `FindOpOverload`; if found,
  emit `mov rdi,rax; mov rsi,rcx; call proc` (SysV AMD64 ABI).

## Parked Workstreams

1. **BASIC frontend** (`blexer.inc` + `bparser.inc`) — partially working, parked.
2. **B2 call-site generic sugar** — `Max<Integer>(a, b)` desugars to B1. After B1 stable.
