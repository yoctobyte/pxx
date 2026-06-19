# Component streaming + LFM loading on the cross targets

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (spun out of feature-cross-target-feature-parity — the
  metaclass/typinfo *read* surface is at parity; full component streaming is not)

## Scope

The **typinfo read surface** is already at cross parity (done in
feature-cross-target-feature-parity): metaclass values, `GetClass`,
`GetOrdProp`/`GetStrProp`, published `set` properties, prop enumeration and
event-method-thunk identity all run output-equal on i386/aarch64/arm32 —
`test_rtti` is wired into the three cross suites (2026-06-19).

What is **not** yet on cross is the higher *component streaming* layer exercised
by `test_streaming`, `test_streaming_enumset`, and `test_lfm`. Compiling those
for any cross target fails at the `GetMethodProp` call with
`target <arch>: builtin/special call not yet supported ()`
(`ir_codegen386.inc:2124` / `ir_codegen_aarch64.inc:1555` /
`ir_codegen_arm32.inc:1742`), in **both** frozen and `-dPXX_MANAGED_STRING`
modes.

## What is missing (to enumerate before starting)

The cross special-call dispatch handles `tkGetMem`/`tkFreeMem`/`tkLength`/`-100`
/`-102`; the x86-64 dispatch additionally handles `-101` (frozen-string
`SetLength`), `-103` (`ReallocMem`), and the lowering that `GetMethodProp`'s
`addr := @PUInt8(instance)[p^.GetRef]` (typed-pointer index + `@`, feeding a
by-value `TMethod` record return) expands to. The first cross failure is that
last item (it fails even under managed strings, so it is not just `-101`).
Porting streaming/LFM means bringing those specials to all three cross backends
(and validating both string modes), then wiring `test_streaming` /
`test_streaming_enumset` / `test_lfm` into the cross suites.

## Acceptance

`test_streaming`, `test_streaming_enumset`, `test_lfm` compile and run
output-equal to x86-64 on i386/aarch64/arm32 (addresses excluded); wired into
the three cross suites; bootstrap + cross-bootstrap stay byte-identical.

## Log
- 2026-06-19 — opened. The three RTTI bugs from the original arc (frozen-string-
  through-pointer read, CPU32 blob stride, sets) are all closed; the remaining
  gap is the streaming-layer special calls above, which is a distinct, larger
  port than the read surface and was scoped out of the parity close-out.
