# Frankonpiler Handover

**Date:** 2026-05-27

## Current Git State

Relevant commits on `master`:

```text
0ecbca7 feat(class): fix class field offsets and method compilation
b4c9e4f docs: update C interop handover
4c21e86 feat(c): add preprocessing stage
4e33759 feat(debug): add runtime compiler tracing
e7f8b2a docs: document shared C library loading
8fcc080 feat(elf): load external C functions
```

## What Works

### Self-hosting fixedpoint
`make bootstrap` and `make test` both pass. `gen2 == gen3`, bit-identical.

### Shared object loading
`uses ctype;` parses `/usr/include/ctype.h`, emits dynamic ELF with `DT_NEEDED libc.so.6`,
resolves symbols via GOT-style `R_X86_64_GLOB_DAT`. Tested: `tolower(65)=97`.

### Local C import
`uses my_c_lib;` compiles local `.c` body into executable. `test/test_c_import.pas` passes.

### C preprocessing (`cpreproc.inc`)
`#include`, include guards, `#define`/`#undef`, object macros, basic function-like macros,
`#if/#ifdef/#ifndef/#else/#endif`. `test/test_c_preprocess.pas` returns 42.

### User-defined classes with fields (NEW)
```pascal
type TCounter = class Value: Integer; end;
var c: TCounter;
begin
  c := TCounter.Create;
  c.Value := 42;
  writeln(c.Value);
end.
```
`test/test_class.pas` passes: `TMyClass.Create` allocates via `GetMem`, field access
via `R_UCLASS_BASE` dynamic record system, correct byte offsets.

### User-defined class methods (NEW)
```pascal
type TCounter = class Value: Integer; procedure Reset; procedure Increment; function Get: Integer; end;
procedure TCounter.Reset; begin Self.Value := 0; end;
procedure TCounter.Increment; begin Self.Value := Self.Value + 1; end;
function TCounter.Get: Integer; begin Result := Self.Value; end;
```
`test/test_class_methods.pas` passes, output: `3`. Method dispatch via `FindUMeth`, implicit
`Self` parameter injection at index 0, `Self.Value` resolved through `UClsFBase`/`UFldOff_`.

### Debug tracing
`pascal26 --debug <src>` enables lexer/parser/preprocessor event traces.

### BASIC frontend (`blexer.inc` + `bparser.inc`)
Parked, partially working.

### Benchmarks
12× faster than FPC; 287-byte hello vs 191KB FPC.

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

## Header / Library Resolution

`uses name;` searches: local dir, `compiler/`, `/usr/include/`. `.h` → external
prototype + dynamic resolve. `ctype` hardcoded → `libc.so.6`. Other headers default
`lib<name>.so`.

## Key Gotchas

- **`break` not supported** — use `done: Boolean` idiom.
- **`ASTIVal` must be `Int64`** — `Integer` truncates $FFFFFFFF in shr codegen.
- **`shr` binop**: save `Tokens[TokPos-1].SOffset/SLen` BEFORE `Next`, then set on AST node.
- **String data layout**: `Strs[i].Offset` = 8-byte length prefix; actual bytes at `+8`.
- **`UnitContent` buffer**: must be global — local `AnsiString` can't hold ~11KB
  `/usr/include/ctype.h`, corrupts stack.
- **`CPExpandFunction` args**: kept in depth-indexed fixed storage, not local open arrays
  (self-hosted stack limitation).
- **Single-char string literals**: `'x'` in source → `AN_INT_LIT` with `ASTTk=Ord(tyChar)`.
  Any code that compares an `AnsiString` against a single-char literal must go through the
  string-vs-char path in codegen.inc (fixed 2026-05-27). Comparisons like `field = 'x'` work
  correctly now.
- **String `+` concatenation**: Now fully supported and implemented! Correct type propagation has been added, and the emitter generates a stack-based temporary concatenation buffer (272 bytes) safely evaluating `a + b` for variables, literals, and chars without register clobbering.
- **Self-evolution bootstrap rule**: Avoid bootstrapping using FPC by default. The compiler should evolve directly using its own built self-hosted seed (`compiler/pascal26`). FPC remains a secondary tool to verify compatibility.
- **Map File (.map) Output**: Implemented robust map file generation (`<outPath>.map`) listing absolute virtual addresses for the executable entry point (`_start`) and all procedures, functions, and class methods. Resolved self-hosted untyped parameter write limitations via the shared `TokChars` buffer and dynamic permissions via `sysfchmod` with decimal `420` (chmod 644).
- **Nested/Recursive Lexer Stack Fix**: Solved a stack overflow segfault in self-hosted mode where local string variable `savedSource` inside `LexAppend` and `CLexAppend` was assigned the entire input `Source` string (e.g. ~280KB) exceeding the 256-byte stack limit (`LOCAL_STR_CAP`). Replaced with a dedicated global string variable `SavedLexSource` (1MB capacity) in `defs.inc`.
- **C Interop / Math User Library (`math.pas`)**: Created a dual-purpose Pascal `math` unit that incorporates both pure Pascal implementations (e.g. `Min`, `Max`, `Power`, `Gcd`, `Lcm`) and transparent C standard library dynamic imports (e.g. `abs`, `labs`) declared via `compiler/math_ext.h` and mapped cleanly to `libc.so.6`.

## Class / Method Implementation Details

- `REC_UCLASS_BASE = 11`. User classes start at this recId.
- `REC_TMYCLASS = 10` is a HARDCODED legacy class; `TMyClass` still routes to it via
  `IsRecordType`. All other user-defined classes use the dynamic UClass system.
- `ParseTypeSection` registers every `class` type via `AddUClass`/`AddUField`.
- Method implementations (`procedure ClassName.MethodName`) are registered via `AddUMeth`
  called from `ParseSubroutine` when `FindUClass(name) >= 0`.
- `Self` is injected as implicit param 0 of type `tyClass`; its `RecName` is set to the
  owner class's recId so `Self.Field` resolves via `FindUField`.
- `TMyClass.Create` / `TCounter.Create` etc.: detected in `ParseFactor`; maps to
  `GetMem(UClsSize_[ci])`.

## Parked Workstreams

1. **BASIC comprehensive** — `test/test_basic_comprehensive.bas` segfaults the compiler.
2. **Pascal classes** — `test/test_class.pas` and `test/test_class_methods.pas` now PASS
   and are in `make test`. This workstream is complete.

## Verification

After `0ecbca7`, `make test` checks (abbreviated):

```sh
make bootstrap   # FPC → gen1 → gen2, cmp gen1==gen2
make test        # all regressions including class tests
```

New in `make test` after this session:
- `test_class.pas` → `1 1 1 42 100 999 888`
- `test_class_methods.pas` → `3`
- `test_math_unit.pas` → `42 999 10 20 256 6 144` (validating both external C math imports and pure Pascal functions across all bootstrap stages)

## Suggested Next Steps

Per `directions.md`:

1. C interop depth: explicit library import syntax, pointer args/returns, mutable buffers,
   C strings, `size_t`, typedef aliases, simple struct layout.
2. Preprocessing breadth driven by real headers (token pasting, stringification, variadic
   macros — only as real headers demand).
3. Exercise additional simple installed library headers (`string.h`, `stdio.h`, etc.) and add
   to `make test`.
4. Protect bootstrappable Pascal core.
