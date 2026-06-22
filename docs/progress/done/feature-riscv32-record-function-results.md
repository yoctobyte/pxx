# riscv32: support record (by-value struct) function results

- **Type:** feature (Track A — riscv32 codegen / ABI)
- **Status:** DONE — 2026-06-23. Record copy (IR_COPY_REC) + by-value record
  function results implemented on riscv32, verified under qemu-system.
- **Owner:** — (Track A)
- **Opened:** 2026-06-22 (found wiring net.pas onto the ESP32-C3 socket smoke, Track B)
- **Closed:** 2026-06-23

## Problem

The riscv32 backend rejects a function whose result is a record (small struct
returned by value):

```
target riscv32: only ordinal/float/pointer/string function results supported yet
```

Per the RISC-V calling convention a struct ≤ 2 XLEN words is returned in
`a0`/`a1`; larger aggregates use the hidden-pointer (sret) convention. Neither
is emitted yet. x86-64 handles record returns (net.pas works on host).

## Impact (why it surfaced)

`lib/rtl/net.pas` exposes `TNetAddress` (a 2-field record: `Host: LongWord;
Port: Integer`) and the helpers `NetAddress`/`NetLoopback` return it by value.
That makes net.pas itself fail to compile for `--target=riscv32`, so the
blocking net facade cannot be used on ESP32-C3. The PAL layer (`platform`) has
no record-returning functions and compiles + links fine for riscv32 — the
ESP32-C3 lwIP socket smoke (`examples/esp32/net-c3`) therefore calls PAL
directly instead of net.pas. This is a real codegen gap, not a reason to
restructure net.pas: returning a small record by value is idiomatic Pascal.

Note Int64 results: a function returning `Int64` works on riscv32 when the
result is consumed directly (the PAL byte-count functions do this); only record
results are blocked here.

## Acceptance

- A function returning a ≤ 2-word record compiles for `--target=riscv32`,
  result marshalled in `a0`/`a1`, caller reads both fields correctly.
- Larger records use the sret hidden-pointer convention.
- `--target=riscv32 -Fulib/rtl/platform/esp` over a program that `uses net`
  (e.g. `NetLoopback`) compiles and links.
- Self-host fixedpoint + existing riscv32 codegen tests stay green.

## Log

- 2026-06-22 — Opened from the ESP32-C3 socket-smoke wiring. PAL-direct path
  works on riscv32; net.pas's by-value `TNetAddress` helpers do not. Sibling
  xtensa gap: `feature-xtensa-stack-args-over-6-words`.

- 2026-06-22 — **Attempted (Track A), HALTED: needs an ESP/qemu-system harness.**
  riscv32 and xtensa are bare-metal/ESP targets — they are NOT in
  `make cross-bootstrap` (only i386/aarch64/arm32 are) and do NOT run under
  qemu-USER here: even `program h; begin Halt(7); end.` for `--target=riscv32`
  hangs (timeout) under `tools/run_target.sh riscv32`. So none of the ESP codegen
  items can be runtime-verified in the host loop; verification requires
  qemu-system / the esp-bare / IDF flow (as this ticket's own repro notes:
  "qemu-system-riscv32 / esp32c3"). Deferred to a session with that harness wired
  (or real esp32c3/s3 hardware) so fixes ship verified, not blind.
- 2026-06-22 — **Verified with a minimal repro + controls (not just the net.pas
  failure).** `function MakeR(x:LongWord;y:Integer):TR` (TR = 2-field record),
  `--target=riscv32` => `only ordinal/float/pointer/string function results
  supported yet`. Controls: an ordinal-result function compiles fine on riscv32,
  and the SAME record-result function compiles fine on x86_64. So the gap is
  specifically riscv32 record-by-value (struct) returns, confirmed.

- 2026-06-22 — **CORRECTION: the ESP harness DOES exist** (the earlier "needs
  qemu-system harness" halt note was wrong — it used qemu-USER). Use
  `tools/esp_run_bare.sh --chip esp32c3|esp32s3 <prog>` (UART vs x86-64 oracle,
  the `make test-esp-bare` pattern); both Espressif qemu-system builds are
  installed. So this item is runtime-verifiable now. Sibling
  feature-riscv32-var-param-forwarding was fixed+verified this way (f67fad2). This
  one remains a real codegen feature (record-return ABI / xtensa stack args), but
  it is no longer blocked on verification.

## Fix log

- 2026-06-23 — **DONE on riscv32** (5789a81). Two gaps: (1) riscv32 had NO record copy at
  all (`y := x` errored "unsupported node") and (2) no record return ABI. Both
  added:
  - `IR_COPY_REC` on riscv32 (`ir_codegen_riscv32.inc`): whole-record byte copy
    via `PXXMemMove(dest, src, count)`. Fixes record assignment broadly.
  - By-value record result via the hidden-destination ABI (PXX-internal, like
    aarch64's x8 / arm32's r12): caller pushes the result-storage address
    (`IRC[node]`, set target-independently in ir.inc) and loads it into **t1**
    right before the call (riscv has no dedicated indirect-result reg); the callee
    prologue (`parser.inc`) stashes t1 into `ProcAggregateDestSym`'s slot; the
    epilogue (`symtab.inc`) `PXXMemMove`s the Result local into [dest] and returns
    the pointer in a0. Forward-declared `EmitSlotAddrRISCV32` in symtab.inc
    (siblings already were). Works for any record size (memcpy), so the
    "≤2 words in a0/a1 vs sret" split is moot for PXX-internal calls.
  - Verified under the Espressif qemu-system harness (`esp_run_bare.sh --chip
    esp32c3`): record copy, a 2-field TNetAddress-shape result, and a 5-field
    (>2 word) result all match the x86-64 oracle. Test
    `test/test_esp_record_result.pas` wired into `make test-esp-bare` (esp32c3).
    make test + cross-bootstrap byte-identical.
  - `net.pas`'s by-value `TNetAddress` helpers now compile for riscv32; `uses net`
    still hits a SEPARATE blocker (external/dynamic lwip_* symbols — not records),
    tracked elsewhere.
  - xtensa record results are a SEPARATE unimplemented gap (the windowed-ABI
    hidden-dest register is fiddlier); the test runs on esp32c3 only.
