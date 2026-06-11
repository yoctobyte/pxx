# Full parameter/result ABI on cross targets

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-11 (user request)

## Motivation

The cross param-copy and call paths only handle ordinal + pointer-sized
arguments and results. `compiler.pas` uses richer signatures — the first wall
when cross-compiling it is `target i386: only ordinal/pointer parameters
supported yet`. Needed for the cross self-host.

## Scope

- **Record / aggregate by value** — pass and return records larger than a
  register (hidden-pointer / by-reference-copy ABI, mirroring the x86-64
  `TypeIsAggregate` + `ProcAggregateDestSym` path) on i386, ARM32, AArch64.
- **Float parameters/results** — per-target FP arg registers (ties to
  feature-cross-float-variant): AArch64 v0..v7, ARM32 VFP/soft-float, i386
  stack/x87, and the SSE class on the SysV side already done for x86-64.
- **`>N` register args** — stack-arg spill on AArch64 (>8) and ARM32 (>4) for
  internal calls (currently a hard error).
- **Open-array / `array of T` params** — the (ptr,len) pair convention on cross
  targets.
- Audit `EmitProcPrologue` param-copy (`parser.inc`) and the internal-call arg
  marshalling in each `ir_codegen_*` for these cases.

## Acceptance

Programs exercising record-by-value, float, open-array, and >N-arg calls compile
and run on i386, ARM32, AArch64 identically to x86-64. New
`test/test_cross_params.pas` in the suites.
