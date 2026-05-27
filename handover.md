# PXX / Frankonpiler Handover

**Date:** 2026-05-27 (updated same day, session 3)

## Current Git State

Relevant commits on `master`:

```text
553dcdc docs: split README; move C interop to C_INTEROP.md
7f72746 docs: note 2026-05-27 FPC bootstrap for generic function record types
7cce611 feat(generics): implement generic functions (B1 syntax)
7c96277 design: generic functions + dialect switches + operator overloading notes
a5cf0a3 generics: fix bootstrap - no Continue, fix for-loop cur clobbering, insert after template method
5079039 Stabilize overloading and achieve full 3-stage self-hosting convergence
546cfd2 feat(interop): add math user library with C imports, fix recursive lexer stack overflow segfault
144e13d feat(map): implement Map File generation (.map) and fix dynamic string concatenation
f907626 docs: update handover for class/method completion
0ecbca7 feat(class): fix class field offsets and method compilation
```

## What Works

### Self-hosting fixedpoint
`make bootstrap` and `make test` both pass. `gen2 == gen3`, bit-identical.

### Generic functions (NEW — B1 syntax)
```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

specialize Max<Integer> as MaxInt;
specialize Max<Char>    as MaxChar;

begin
  writeln(MaxInt(3, 7));    { 7 }
  writeln(MaxChar('a','z')); { z }
end.
```
Also: generic procedures, `var` params (Swap), multi-param generics (Clamp).
`test/test_generic_func.pas` passes: `7 10 3 4 5 1 10 99 42`.

Implementation reuses `TemplateTokens`/`SpecializeStream` (same engine as class generics).
`TGenericFunc` buffered at parse time; `ParseTopLevelSpecialize` injects specialization
into token stream and calls `ParseSubroutine` immediately.

### Class generics
Previously implemented. `specialize TList<Integer>` etc.

### Overloading
Routine declarations accept `overload;`, while overload resolution remains
permissive when it is omitted. Operator implementations are supported for
class operands:

```pascal
procedure PrintVal(x: Integer); overload;
operator + (a, b: TPoint): TPoint;
```

`test/test_overloading.pas` and `test/test_op_overload.pas` pass under the
self-hosted compiler.

### Loop control
`break` and `continue` are supported in `while`, `for`, and `repeat` loops.
`continue` targets the condition for `while`, the update step for `for`, and
the `until` condition for `repeat`. Nested-loop behavior is covered by
`test/test_loop_control.pas`.

### Compiler identity and Pascal conditionals
`PXX` is the provisional compiler name; the executable remains
`compiler/pascal26` while naming is unsettled. PXX predefines `PXX`, not
`FPC`. It supports `{$define}`, `{$undef}`, `{$ifdef}`, `{$ifndef}`,
`{$else}`, and `{$endif}`, plus accepted `{$mode objfpc}` / `-Mobjfpc`
markers and command-line `-dNAME` / `-uNAME`. Coverage is in
`test/test_pascal_directives.pas`. `{$strict_overload on}` and
`--strict-overload` enforce explicit routine overload declarations, covered by
`test/test_strict_overload.pas` and `test/test_strict_overload_error.pas`.
See `COMPATIBILITY.md` for the compatibility inventory.

### Exceptions (Phases 1-2 plus exact typed dispatch)
Catch-all exception blocks, exact user-class typed handlers, finalizers,
expression raises, and handler re-raise are implemented:

```pascal
try
  raise 42;
except
  writeln('caught');
end;

try
  writeln('work');
finally
  writeln('cleanup');
end;

try
  raise TParseError.Create;
except
  on E: TParseError do writeln(E.Code);
end;
```

Raised values cross procedure and Pascal-unit boundaries through generated
integer-state `setjmp`/`longjmp` helpers and an 80-byte linked frame per
active `try`. An `on E: TClass do` clause binds a raised user-class object and
matches its declared class exactly. Unhandled raises print
`Unhandled exception` and exit with status 1; `--no-unhandled-handler` and
`-fno-unhandled-handler` suppress that message. Class inheritance, a built-in
`Exception` hierarchy/message constructor, inherited matches, and richer
unhandled diagnostics remain subsequent work from
`docs/exceptions-plan.md`. `Exit`, `break`, and `continue` track the nearest
target's exception depth, execute crossed finalizers in order, and pop only
protected frames crossed by the jump.

### User-defined classes with fields and methods
```pascal
type TCounter = class Value: Integer; procedure Increment; function Get: Integer; end;
```
`test/test_class.pas` → `1 1 1 42 100 999 888`.
`test/test_class_methods.pas` → `3`.

### Shared object loading
`uses ctype;` parses `/usr/include/ctype.h`, emits dynamic ELF with `DT_NEEDED libc.so.6`.
Tested: `tolower(65)=97`.

### Local C import
`uses my_c_lib;` compiles local `.c` body into executable.

### C preprocessing (`cpreproc.inc`)
`#include`, include guards, `#define`/`#undef`, object macros, basic function-like macros,
`#if/#ifdef/#ifndef/#else/#endif`. `test/test_c_preprocess.pas` returns 42.

### Math user library (`compiler/math.pas`)
Pure Pascal (`Min`, `Max`, `Power`, `Gcd`, `Lcm`) + C import bridge (`abs`, `labs`).
`test/test_math_unit.pas` → `42 999 10 20 256 6 144`.

### Map file output
`<outPath>.map` lists absolute virtual addresses for `_start` and all procedures/methods.

### Debug tracing
`pascal26 --debug <src>` enables lexer/parser/preprocessor event traces.

### Benchmarks (2026-05-27)
Compiler self-compilation (30 runs):
- pascal26: 68.4 ms ± 11.5 ms
- FPC: 598.5 ms ± 85.4 ms — **8.75× faster**

Hello world ×20 batch (10 runs):
- pascal26: 17.3 ms ± 7.4 ms
- FPC: 1.201 s ± 0.069 s — **~70× faster**

Binary sizes: hello world = **325 bytes** (FPC: 191 KB).

## Architecture

- `compiler/compiler.pas` — main entry, includes all `.inc` files
- Include chain: `defs.inc` → `lexer.inc` → `clexer.inc` → `blexer.inc` → `emit.inc` →
  `symtab.inc` → `parser.inc` → `codegen.inc` → `cparser.inc` → `bparser.inc` →
  `elfwriter.inc` → `cpreproc.inc`
- Single-pass: source → tokens → AST → x86-64 bytes → ELF write
- No linker, no stdlib, no runtime
- Static programs: one load segment, no dynamic section
- Dynamic programs (any external call): emit PT_INTERP, PT_DYNAMIC, DT_NEEDED, GOT,
  plt-style indirect calls

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
  String-vs-char path in codegen.inc handles comparisons like `field = 'x'`.
- **String `+` concatenation**: emitter generates 272-byte stack temp buffer; correct
  type propagation across variables, literals, and chars.
- **Nested/Recursive Lexer Stack Fix**: `SavedLexSource` is a 1 MB global in `defs.inc`.
  Local `AnsiString` for saved source caused stack overflow (256-byte `LOCAL_STR_CAP` limit).
- **New record types require FPC bootstrap**: `symtab.inc` hardcodes all record types.
  `TGenericFunc` and `TPendingGFSpec` were added 2026-05-27; old seed didn't know them,
  requiring bootstrap. After bootstrap, self-hosting resumed at fixedpoint.
- **`ParseTopLevelSpecialize` semicolon**: do NOT call `Eat(tkSemicolon)` before
  `SpecializeStream`. Insert must happen while CurTok=`;`; otherwise CurTok after
  `ParseSubroutine` lands inside the next `specialize` statement.
- **Generic specialization scratch storage**: `SpecializeTokens` and
  `SpecializeTemplateName` are globals. A local temporary token array corrupted
  self-hosted generic specialization.
- **`REC_UCLASS_BASE` must exceed all hardcoded type IDs**: hardcoded types 1–14 live in
  `symtab.inc` (`REC_TTEMPLATE=11` … `REC_TPENDINGGFSPEC=14`). `REC_UCLASS_BASE` was 11
  — user class 0 got recId=11, hitting the `if rec=REC_TTEMPLATE` branch in
  `RecFieldOffset`/`RecFieldType` instead of the user-class path. All field offsets
  returned 0 → both X and Y fields of a user class always read from offset 0 → last
  written value wins for all fields. Fixed: `REC_UCLASS_BASE=15` in `defs.inc`. Rule:
  whenever a new hardcoded record type is added to `symtab.inc`, bump `REC_UCLASS_BASE`
  past the new max.
- **Self-evolution bootstrap rule**: evolve using self-hosted seed by default. FPC is
  recovery path only. Note any use of FPC bootstrap in `compiler/usernotes.md`.
- **Map File output**: uses shared `TokChars` buffer; `sysfchmod` with decimal `420`
  (chmod 644) for permissions.

## Class / Method Implementation Details

- `REC_UCLASS_BASE = 15`. User classes start at this recId (was 11 — see gotcha below).
- `REC_TMYCLASS = 10` is a HARDCODED legacy class; `TMyClass` still routes to it via
  `IsRecordType`. All other user-defined classes use the dynamic UClass system.
- `ParseTypeSection` registers every `class` type via `AddUClass`/`AddUField`.
- Method implementations (`procedure ClassName.MethodName`) registered via `AddUMeth`
  from `ParseSubroutine` when `FindUClass(name) >= 0`.
- `Self` injected as implicit param 0 of type `tyClass`; `RecName` set to owner class
  recId so `Self.Field` resolves via `FindUField`.
- `.Create` detected in `ParseFactor`; maps to `GetMem(UClsSize_[ci])`.

## Dialect / Compiler Switches

The initial identity/conditional layer is implemented: `PXX` is predefined,
`FPC` is not, named define conditionals nest, and `-dNAME`, `-uNAME`, and
`-Mobjfpc` are accepted. The first semantic switch is also implemented:
- `strict_overload` (default off): `{$strict_overload on}` /
  `--strict-overload` requires explicit `overload` on overloaded procs.
- `--no-unhandled-handler` / `-fno-unhandled-handler`: suppresses the generic
  Phase 1 unhandled-exception diagnostic while preserving exit status 1.
- `generic_syntax` (default b1): b1=top-level `generic function`+`specialize as`, a=type-section style.

## Operator Overloading

Syntax:
```pascal
operator < (a, b: TWeight): Boolean;
begin Result := a.Value < b.Value; end;

operator + (a, b: TPoint): TPoint;
var r: TPoint;
begin r := TPoint.Create; r.X := a.X + b.X; r.Y := a.Y + b.Y; Result := r; end;
```

`test/test_op_overload.pas` passes with the self-hosted compiler:
```
1 0 1 0 1 0 10 6
```

### Implementation

- `defs.inc`: 4 parallel arrays (`OvrlOpKind`, `OvrlTypeKind`, `OvrlRecId`, `OvrlProcIdx`)
  + `OvrlCount`. `MAX_OP_OVERLOADS=64`.
- `symtab.inc`: `RegisterOpOverload(opKind, typeKind, recId, procIdx)` and
  `FindOpOverload(opKind, typeKind, recId) → procIdx`.
- `parser.inc`: `ParseOperatorDef` — called from `ParseProgram` when `CurTok='operator'`.
  Lookahead inside `()` to find first `:` at depth=1, reads type name via
  `GetTokenStrFromRaw(SOffset, SLen)`. Injects `function __op__NN (` into token stream,
  calls `ParseSubroutine`, then `RegisterOpOverload`.
- `parser.inc`/`ParseTypeSection`: Boolean termination prevents the type section
  loop consuming `operator` as a type name without relying on `break`.
- `parser.inc`/`ParseSubroutine`: `ptypesRec[i] := LastTypeRecId` after `ParseTypeKind`;
  sets `Syms[idx].RecName := ptypesRec[i]` for class/record params so field lookups work.
- `codegen.inc`/`AN_BINOP`: before all other binop handling, call `FindOpOverload`; if
  found, emit `mov rdi,rax; mov rsi,rcx; call proc` (SysV AMD64 ABI).

### Bootstrap resolution

The initial bootstrap failure came from `Break` statements used before loop-control
support existed in the self-hosted compiler. Those internal loops now use Boolean
termination. Generic specialization was also stabilized through global scratch
token storage and field-by-field token copies. `make bootstrap` and `make test`
both converge again.

## Parked Workstreams

1. **BASIC frontend** (`blexer.inc` + `bparser.inc`) — partially working, parked.
2. **B2 call-site generic sugar** — `Max<Integer>(a, b)` desugars to B1. After B1 stable.

## Suggested Next Steps

1. **Compiler switches** — add further semantic switches, beginning with a
   deliberate policy for alternative generic syntax/modes.
2. **C interop depth** — pointer args/returns, C strings, `size_t`, typedef aliases,
   simple struct layout. Driven by real header needs.
3. **Exercise more stdlib headers** — `string.h`, `stdio.h`, add to `make test`.
