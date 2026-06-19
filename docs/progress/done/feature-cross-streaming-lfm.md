# Component streaming + LFM loading on the cross targets

- **Type:** feature
- **Status:** done
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
- 2026-06-19 — **DONE** (commit 25eb50d). The first cross failure turned out to
  be the frozen-string `SetLength` special (`-101`), not the `GetMethodProp`
  lowering (that pattern already worked — test_streaming binds `OnGo` on i386).
  Four gaps closed, in order of discovery:
  1. `-101` (frozen-string SetLength) ported to i386/aarch64/arm32: store the
     new length into the inline 8-byte prefix (i386/arm32 zero the high dword;
     aarch64 stores the full xN). Local/global buffer + string-param-slot cases,
     mirroring x86-64 `EmitStoreStrLen`.
  2. `typinfo.pas` enum value-name table read via a new 8-byte-padded
     `TEnumValSlot` — the blob uses uniform 8-byte slots, but `array of PString`
     stepped the native 4-byte pointer on 32-bit and read every other entry as
     the zeroed high half (nil) → `GetEnumValue` crashed (enum + set streaming).
  3. `resources.pas` `TResEntry` padded on CPU32 (24-byte stride) so
     `FindResource` walks the `{$R}` table correctly (test_lfm).
  4. arm32/aarch64 string equality: aarch64 had **no** frozen `string=string`
     path (compared buffer addresses → always unequal); and a frozen string
     reached through a pointer deref / pointer field (`pstr^`,
     GetClass's `entries[i].NamePtr^ = name`) is tagged `tyPointer`, which both
     backends rejected from their string-eq branch and fell to an integer
     compare. Both now decode a `tyPointer` operand as a frozen string when the
     other operand is a genuine string (matches i386/x86-64). These two were
     pre-existing latent cross bugs surfaced by GetClass.
  `test_streaming` / `test_streaming_enumset` / `test_lfm` are wired into the
  three cross suites (output-equal to x86-64). `make test` byte-identical
  fixedpoint + `--threadsafe`; `make cross-bootstrap` byte-identical on all 3.
