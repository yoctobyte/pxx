---
prio: 40
track: A
resolved: e4e68e88
---

# advisory: fpc-bootstrap canary red at 603cf2bd — forwards drift + enum-arg from b310

- **Type:** advisory regression (FPC-seed canary, NOT self-host — self-host fixedpoint
  stayed byte-identical throughout; only "FPC still accepts the source" broke).
- **Found:** borg tstate STILL-RED, bisect bad `603cf2bda859` last good `9ae7a3617ccb`.
- **Resolved:** e4e68e88, 2026-07-14.

## Root cause (4 errors, 2 kinds)

FPC compiles single-pass and strict; pxx prescans headers and is lax on
enum<->int. Drift accumulates silently until the canary runs:

1. Missing forwards (use-before-body in linear include text):
   - `EnableExceptionRuntime` (parser.inc:7875 use, body :21763) → forwards.inc
   - `IsASTLValue` (ir.inc:798 use, body :1420) → forwards.inc
   - `IREmitNodeRISCV32` forward sat BELOW its first two call sites in
     ir_codegen_riscv32.inc → moved above `EmitAnsiStringFromNodeRISCV32`
2. `cparser.inc` (b310 anonymous bit-fields): `TypeSize(IntToTypeKind(fTk))`
   fed a `TTypeKind` to the int→enum converter; `TypeSize` takes `TTypeKind`
   directly. Semantically identical under pxx, type error under FPC.

## Gate
FPC 103941 lines compiled clean; `--tier quick` green; self-host fixedpoint
byte-identical; `fpc-bootstrap#00` PASS locally.

## Note
The bisect blamed only 603cf2bd, but 3 of 4 errors predate it (FPC stops at
first module failure, so older drift hid behind whichever error came first).
