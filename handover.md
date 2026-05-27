# Frankonpiler Handover

**Date:** 2026-05-27

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
- **Self-evolution bootstrap rule**: evolve using self-hosted seed by default. FPC is
  recovery path only. Note any use of FPC bootstrap in `compiler/usernotes.md`.
- **Map File output**: uses shared `TokChars` buffer; `sysfchmod` with decimal `420`
  (chmod 644) for permissions.

## Class / Method Implementation Details

- `REC_UCLASS_BASE = 11`. User classes start at this recId.
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

## Parked Workstreams

1. **BASIC frontend** (`blexer.inc` + `bparser.inc`) — partially working, parked.
2. **Operator overloading** — needed for generic functions to work on user-defined types.
   Design in `compiler/usernotes.md`. Not yet started.
3. **B2 call-site generic sugar** — `Max<Integer>(a, b)` desugars to B1. After B1 stable.

## Suggested Next Steps

1. **Operator overloading** — `operator <(a, b: TVector): Boolean`. Required for generic
   functions to be useful beyond built-in types. Design already documented.
2. **Compiler switches** — pragma `{$SWITCH value}` and `--switch=value` CLI flag.
   `strict_overload` as first concrete switch.
3. **C interop depth** — pointer args/returns, C strings, `size_t`, typedef aliases,
   simple struct layout. Driven by real header needs.
4. **Exercise more stdlib headers** — `string.h`, `stdio.h`, add to `make test`.
