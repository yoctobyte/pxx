# IR Backend Status

**Updated:** 2026-05-31

## Current State: Fixedpoint Achieved

The IR backend reached full IR-to-IR self-recompile fixedpoint on 2026-05-28.
Three generations of
compiler, each compiled via the IR path, produce a bit-identical binary.

```
FPC → stage0 → gen1 (IR) → gen2 (IR-by-IR) → cmp gen1 gen2: identical
```

See [historic/selfcompile-milestone.md](historic/selfcompile-milestone.md) for the full account.

## What the IR Backend Does

The IR path is a two-stage pipeline:

1. `IRLowerAST` (`ir.inc`) — walks the AST and emits a linear IR sequence
2. `IREmitMachineCode` (`ir_codegen.inc`) — translates IR nodes to x86-64 bytes

The IR backend is the only active backend and the compiler bootstraps through
it. The obsolete direct AST→x86-64 emitter was archived under `historic/` on
2026-05-31.

## Key Files

| File | Role |
|------|------|
| `compiler/ir.inc` | AST → IR lowering (`IRLowerAST`, `IRLowerAddress`) |
| `compiler/ir_codegen.inc` | IR → x86-64 (`IREmitNode`, `IREmitMachineCode`) |
| `compiler/exception_emit.inc` | Generated exception-runtime helper bytes |
| `historic/direct-codegen-legacy.inc` | Archived obsolete direct emitter |

## Invoking

The IR backend is the default; no flag needed:

```sh
./compiler/pascal26 source.pas /tmp/out
```

`--experimental-ir-codegen` is accepted as a deprecated no-op. Add `--dump-ir`
to print the IR before emission:

```sh
./compiler/pascal26 --dump-ir source.pas /tmp/out
```

## Bugs Fixed for Fixedpoint

### 1. `ResolveNodeRec` missing `AN_FIELD` case in `AN_INDEX`

`ResolveNodeRec` maps an AST node to its record type for field-offset
lookups. For `AN_INDEX` it only handled the `AN_IDENT` base case
(e.g. `Syms[i]`). When the base was `AN_FIELD` (e.g. `Procs[i].Params[j]`),
it returned `REC_NONE`, making every `TParam` field map to offset 0.
All reads of `TypeKind`, `SymIdx`, `IsRef`, `IsArray`, and `Name` aliased
the same byte, so `MatchProcCall` received symbol indices instead of type
kinds and every proc call type-check failed.

Fix: added `else if ASTKind[ASTLeft[node]] = AN_FIELD then Result :=
ResolveNodeRec(ASTLeft[node])` in `compiler/symtab.inc`.

### 2. `MAX_TOKENS` too small; `ASTNodeCount` was cumulative

The token array is pre-allocated for the whole source file. At 131072
tokens the compiler ran out before finishing its own source after exception
handling grew the line count. `ASTNodeCount` was also never reset between
functions, turning `MAX_AST` into a global cap instead of a per-function cap.

Fix A: `MAX_TOKENS` doubled to 262144 (`compiler/defs.inc`).
Fix B: `ASTNodeCount := 0` reset after each `CompileAST` call
(`compiler/parser.inc`). `MAX_AST` is now a per-function ceiling; any
codebase size is supported.

## IR Coverage

The IR backend handles the full compiler source, including:

- All control flow: `if`, `while`, `for`, `repeat`, `case`, `break`,
  `continue`, `exit`
- Procedure and function calls (SysV AMD64 ABI)
- All core binary operators and unary operators
- Record field access and array indexing, including chained
  `Procs[i].Params[j]` patterns
- String semantics: address passing, `rep movsb` store, inline concatenation
- `Ord`/`Chr`/integer cast intrinsics
- Set-membership (`in`) tests
- Exception frames (`try/except`, `try/finally`, `raise`)
- Operator overloading (the former `test_op_overload.pas` IR red is resolved)
- Typed pointers: named aliases `PFoo = ^TFoo`, indexing `p[i]`, `p^.field`,
  casts `PType(expr)`, all with correct element-size stride
- Published RTTI end-to-end (`compiler/typinfo.pas`): GetClass / GetPropList /
  Get|SetOrdProp / Get|SetStrProp / SetMethodProp / set properties.
  `test/test_rtti.pas` round-trips.

## Known Gaps

The IR backend is self-consistent. Remaining backend work:

- Optimization passes (none planned yet — this is by design for now)
- Some edge cases in C-frontend and BASIC-frontend paths
- Dedicated 32-byte set algebra and comparison semantics

## Building and Testing

```sh
make test        # runs full suite including IR tests
make bootstrap   # rebuild seed via FPC if needed
```

IR-specific tests live in `test/test_ir_*.pas`.
