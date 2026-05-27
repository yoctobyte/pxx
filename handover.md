# Frankonpiler Handover

**Date:** 2026-05-27 (updated same day, session 2)

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
- `SpecializeStream(templateName, param, concreteName, concreteKind)`: substitutes template
  param with concrete type, inserts at `TokPos`, shifts existing tokens right.
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

- **`break` not supported** — use `done: Boolean` idiom.
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

## Dialect / Compiler Switches (planned)

Documented in `compiler/usernotes.md`. Key planned switches:
- `strict_overload` (default off): require explicit `overload` directive on overloaded procs.
- `generic_syntax` (default b1): b1=top-level `generic function`+`specialize as`, a=type-section style.

## Operator Overloading (NEW — implemented but bootstrap pending)

Syntax:
```pascal
operator < (a, b: TWeight): Boolean;
begin Result := a.Value < b.Value; end;

operator + (a, b: TPoint): TPoint;
var r: TPoint;
begin r := TPoint.Create; r.X := a.X + b.X; r.Y := a.Y + b.Y; Result := r; end;
```

`test/test_op_overload.pas` passes with FPC-compiled binary:
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
  `GetTokenStrFromRaw(Tokens[i])`. Injects `function __op__NN (` into token stream,
  calls `ParseSubroutine`, then `RegisterOpOverload`.
- `parser.inc`/`ParseTypeSection`: `else if CaseEqual(CurTok.SVal,'operator') then Break`
  prevents type section loop consuming `operator` as a type name.
- `parser.inc`/`ParseSubroutine`: `ptypesRec[i] := LastTypeRecId` after `ParseTypeKind`;
  sets `Syms[idx].RecName := ptypesRec[i]` for class/record params so field lookups work.
- `codegen.inc`/`AN_BINOP`: before all other binop handling, call `FindOpOverload`; if
  found, emit `mov rdi,rax; mov rsi,rcx; call proc` (SysV AMD64 ABI).

### Bootstrap still broken

`make bootstrap` fails: FPC-compiled binary compiles user programs fine but crashes on
`compiler.pas` itself with `error: undefined variable ()` at line ~8944.

**Debug state** (session ended mid-investigation):
- Debug prints added to `ParseLValueAST` (parser.inc line ~597) and `CompileLValueAddress`
  (line ~909) — **REMOVE these before committing**.
- Output: `DBG ParseLValueAST prevTok=26836 name=[] TokPos=26837 kind=77 CurKind=77`
- `kind=77` = `tkSemicolon` (counted from enum: tkSemicolon is 77th in `TTokenKind`).
- Two consecutive semicolons at token positions 26836–26837, empty name.
- `ParseLValueAST` is called with `idx=-1`; `prevTok=TokPos-1` unexpectedly points to
  a semicolon, not an identifier. Parser consumed `;` token BEFORE arriving at a point
  that tried to look up a variable name.
- Hypothesis: something in compiler.pas (near the end — token 26836 is near EOF of the
  ~27K-token stream) causes the parser to misparse a statement. Likely a construct in the
  new operator-overloading code or in the `OvrlCount`/`OvrlOpKind` initialization section
  of the main `begin` block that the self-hosted compiler doesn't handle.
- **Candidate constructs to check**: does compiler.pas `begin` block initialize `OvrlCount`?
  (It doesn't — should be fine as globals zero-init.) Check if parser.inc debug prints
  themselves cause issues (they reference `StdErr` which may not be in scope).
- Most likely next step: remove debug prints, binary-search the issue by temporarily
  commenting out sections of the new code in defs.inc/parser.inc/symtab.inc to find which
  new construct the self-hosted compiler chokes on.

## Parked Workstreams

1. **BASIC frontend** (`blexer.inc` + `bparser.inc`) — partially working, parked.
2. **B2 call-site generic sugar** — `Max<Integer>(a, b)` desugars to B1. After B1 stable.

## Suggested Next Steps

1. **Fix bootstrap** — remove debug prints from `parser.inc`, then binary-search the
   `error: undefined variable ()` at token 26836. See debug state above.
2. **Add test_op_overload to Makefile** — `make test` should run it.
3. **Compiler switches** — pragma `{$SWITCH value}` and `--switch=value` CLI flag.
   `strict_overload` as first concrete switch.
4. **C interop depth** — pointer args/returns, C strings, `size_t`, typedef aliases,
   simple struct layout. Driven by real header needs.
5. **Exercise more stdlib headers** — `string.h`, `stdio.h`, add to `make test`.
