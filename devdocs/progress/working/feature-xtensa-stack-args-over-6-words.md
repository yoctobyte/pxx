---
prio: 65  # user 2026-08-02: xtensa is the PRIMARY ESP target (S2/S3 hardware)
---

# xtensa: support calls/definitions with more than 6 parameter words

- **Type:** feature (Track A — xtensa codegen / ABI)
- **Status:** working
- **Owner:** track-A-S
- **Opened:** 2026-06-22 (found during PAL esp object-smoke, Track B)

## Problem

The xtensa backend caps both function **definitions** and **call sites** at 6
parameter words:

- `compiler/parser.inc:10557` / `:10573` — defining a routine with > 6 parameter
  words → `target xtensa: more than 6 parameter words not yet supported`.
- `compiler/ir_codegen_xtensa.inc:1528` — a call passing > 6 argument words →
  `target xtensa: more than 6 call argument words not supported yet`.

riscv32 already allows 8 (`parser.inc:10523`); x86-64/aarch64/arm32 spill to the
stack. xtensa needs the same: arguments beyond the in-register set (a2..a7 for
Call0, the rotated window for windowed) go on the outgoing stack frame per the
Xtensa ABI; the callee reads them from its incoming frame.

## Impact (why it surfaced)

The **esp32s3 (xtensa) PAL object build is blocked**. `PalBackendVforkAndExec`
(`lib/rtl/platform/{posix,esp}/platform_backend.pas`) takes 7 parameter words
(`path, argv, envp, stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd`), so
`--target=xtensa --xtensa-abi=windowed -Fulib/rtl/platform/esp
test/lib_platform_esp.pas` fails at pascal26:647. This predates the PAL
datagram/introspection work — it landed with the process-spawning feature. The
**esp32c3 (riscv32) build is fine** (8-word cap) and imports all expected
`lwip_*`/process symbols.

No workaround applied: the 7-word `PalBackendVforkAndExec` signature is the
honest one (mirrors the POSIX fork+exec plumbing). It stays clean; the fix is in
the compiler.

## Acceptance

- A routine defined with 7+ parameter words compiles for `--target=xtensa`
  (both Call0 and windowed ABIs), args beyond the register set passed on the
  stack, callee reads them correctly.
- A call site passing 7+ argument words marshals the overflow to the outgoing
  stack slots.
- `--target=xtensa --xtensa-abi=windowed -Fulib/rtl/platform/esp
  test/lib_platform_esp.pas <obj>` emits an object importing the expected
  `lwip_*` symbols (parity with the riscv32 esp object smoke).
- Self-host fixedpoint + existing xtensa codegen tests stay green.

## Log

- 2026-06-22 — Opened from a Track B PAL esp object-smoke: riscv32 esp object
  compiles and imports `lwip_sendto/recvfrom/poll/getsockopt/getsockname`;
  xtensa esp object fails on the pre-existing 7-word `PalBackendVforkAndExec`.
  Related broader target ticket: `feature-esp32-idf-xtensa`.

- 2026-06-22 — **Attempted (Track A), HALTED: needs an ESP/qemu-system harness.**
  riscv32 and xtensa are bare-metal/ESP targets — they are NOT in
  `make cross-bootstrap` (only i386/aarch64/arm32 are) and do NOT run under
  qemu-USER here: even `program h; begin Halt(7); end.` for `--target=riscv32`
  hangs (timeout) under `tools/run_target.sh riscv32`. So none of the ESP codegen
  items can be runtime-verified in the host loop; verification requires
  qemu-system / the esp-bare / IDF flow (as this ticket's own repro notes:
  "qemu-system-riscv32 / esp32c3"). Deferred to a session with that harness wired
  (or real esp32c3/s3 hardware) so fixes ship verified, not blind.
- 2026-06-22 — **Verified the threshold empirically (not just inferred from one
  compile error).** Programs defining + calling a procedure with N Integer
  params, `--target=xtensa`: `5` and `6` params compile; `7` and `8` FAIL with
  `more than 6 parameter words not yet supported`. Holds for BOTH `--xtensa-abi=
  windowed` and Call0 (bare). The definition-site error (parser.inc:10557) fires
  first for a 7-word routine, which is the `PalBackendVforkAndExec` (7 words)
  case. So: xtensa supports <= 6 param words, >6 does not compile — confirmed,
  not assumed.

- 2026-06-22 — **CORRECTION: the ESP harness DOES exist** (the earlier "needs
  qemu-system harness" halt note was wrong — it used qemu-USER). Use
  `tools/esp_run_bare.sh --chip esp32c3|esp32s3 <prog>` (UART vs x86-64 oracle,
  the `make test-esp-bare` pattern); both Espressif qemu-system builds are
  installed. So this item is runtime-verifiable now. Sibling
  feature-riscv32-var-param-forwarding was fixed+verified this way (f67fad2). This
  one remains a real codegen feature (record-return ABI / xtensa stack args), but
  it is no longer blocked on verification.

- 2026-06-23 — Scoped (Track A). The cap is at parser.inc ~10823/10840 (callee
  param copy) + ir_codegen_xtensa.inc ~1549 (call site). Lifting it needs INCOMING
  STACK-ARG layout: words 0-5 stay in a2-a7 (Call0) / a10-a15 (windowed), words 6+
  go on the stack and the callee reads them from its incoming frame. **Call0** is
  the tractable half (classic moving-sp overflow; offset = frame size + saved regs
  + (k-6)*4). **Windowed is the rabbit hole** and is exactly what the blocked PAL
  needs (`--xtensa-abi=windowed`): the `entry`/`retw` window rotation plus the
  [sp-16] window spill area make the overflow-arg offset frame-and-window
  dependent — not a clean extension. Deferred as a focused sub-task; needs careful
  windowed frame-layout work (and the qemu-system harness, which now exists, to
  verify). The sibling ESP items (var->var forwarding, record results) are DONE
  and verified this session; this is the remaining one.

## Reference implementation, measured from xtensa gcc (2026-08-02)

Asked how other toolchains handle this (Arduino, MicroPython, ESP-IDF — all gcc).
**They do not work around it.** No pointer-struct packing: they implement the
ABI, first N words in registers and the rest in the caller's outgoing stack
frame. Taken from the `xtensa-esp32s3-elf-gcc` that ships with the installed IDF,
`-O2`, 9 int args:

**Caller (windowed)** — args 1..6 in `a10..a15`, args 7,8,9 written to the
outgoing area at `sp+0/4/8` *before* the call:

```asm
caller:
    entry   sp, 48
    movi.n  a8, 9
    s32i.n  a8, sp, 8        ; arg 9
    movi.n  a8, 8
    s32i.n  a8, sp, 4        ; arg 8
    movi.n  a8, 7
    s32i.n  a8, sp, 0        ; arg 7
    movi.n  a15, 6 ... movi.n a10, 1
    call8   callee
```

**Callee (windowed)** — `entry sp,32` lowers sp by the frame size, so the
caller's `sp+0/4/8` is read back at `sp+32/36/40`:

```asm
callee:
    entry   sp, 32
    l32i.n  a8, sp, 32       ; arg 7
    l32i.n  a9, sp, 36       ; arg 8
    l32i.n  a2, sp, 40       ; arg 9
```

**Callee (Call0, `-mabi=call0`)** — no window rotation and no `entry`, so the
same slots are read directly at `sp+0/4/8`:

```asm
callee:
    l32i.n  a9, sp, 0
    l32i.n  a10, sp, 4
    l32i.n  a2, sp, 8
```

So the two ABIs differ only in whether the incoming offset is biased by the
`entry` frame size — the caller side is identical. That is the whole fix.

## riscv32 is NOT working by luck — checked

The Problem section above says "riscv32 already allows 8", which reads as a
higher cap of the same kind. It is not: riscv32 **spills to the stack properly**.
Measured with a 12-integer-argument function compiled `--target=riscv32` and run
under `qemu-riscv32`:

```
expect:  1 2 3 4 5 6 7 8 9 10 11 12   sum=78
riscv32: 1 2 3 4 5 6 7 8 9 10 11 12   sum=78     (identical to x86-64)
```

9, 10 and 12 parameter words all compile and pass correctly. So this is an
**xtensa-only implementation gap**, not a shared limit that riscv32 happens to
sit under — and there is a working in-tree implementation of the same idea to
copy from.

## Line numbers refreshed

The Problem section's citations have drifted. Current sites:

- `compiler/parser.inc:26978` and `:26994` — definition cap
- `compiler/ir_codegen_xtensa.inc:1774` — call-site cap
- `compiler/ir_codegen_xtensa.inc:1512` — a third one the ticket does not
  mention: `constructor with more than 6 parameter words not supported`

## Priority: xtensa is the PRIMARY ESP target (user, 2026-08-02)

Raised 45 -> 65. The user's ESP32 devices are mostly **S2 and S3, both xtensa**;
older models are out of scope. So this ticket is not a nice-to-have behind
riscv32 — it is the gate on the ESP target that actually matters to the person
using it.

Confirmed the same day that this cap is the **only** thing stopping the xtensa
ESP PAL build:

```
--target=xtensa --xtensa-abi=windowed --platform=esp \
  -Fulib/rtl -Fulib/rtl/platform/esp test/lib_platform_esp.pas
  -> pascal26:961: error: target xtensa: more than 6 parameter words not yet supported
```

That is the first and only error; nothing else in the ESP PAL is refused.

### Matching gcc is required, not merely convenient

An ABI is a contract with the *other* compiler, and on ESP both directions are
crossed constantly:

- pxx-built code **calls into** IDF / FreeRTOS / lwIP, all gcc-built. A call
  with >6 argument words must leave them where gcc's callee looks.
- IDF **calls into** pxx — `app_main` today, plus any callback or ISR
  registered later. Those must read arguments where gcc's caller left them.

So the alternative sometimes suggested — packing the overflow into a
caller-allocated struct and passing a pointer — is not an option here: it is
ABI-incompatible the moment either boundary is crossed with >6 words, and it
would leave two conventions to keep straight. Doing exactly what gcc does is
both simpler and the only interoperable answer. The measured reference codegen
is in the section above.

(Aside, since it came up: a Pascal `var` parameter costs **one** word — it
passes an address — so it needs no heap and does not itself push a signature
over the cap. The overflow area is plain outgoing stack, never heap.)

### QEMU covers S3 but not S2

`qemu-system-xtensa` in the installed IDF offers machines **`esp32`** and
**`esp32s3`** only — there is no `esp32s2`. So this work is verifiable headless
for S3, and S2 needs real silicon
([[feature-esp-hardware-flash-validation]]).

## Do WINDOWED first — it is the profile that matters (user, 2026-08-02)

The acceptance above asks for "both Call0 and windowed" without ranking them.
They are not equally valuable:

| | ABI | what it gets you |
| --- | --- | --- |
| **ESP-IDF profile** | **windowed** (`--xtensa-abi=windowed`, as `examples/esp32/hello-s3` uses) | lwIP, Wi-Fi/BT, esp_netif, FreeRTOS, the whole driver set |
| bare (`--esp-profile=bare`) | Call0 — *required*, windowed needs window-overflow handlers and a vecbase bare-metal never installs (`compiler.pas:634`) | MMIO only |

**Bare-metal is not a smaller version of the IDF profile; it is a different,
much weaker device.** `lib/rtl/platform/esp/platform_backend.pas` carries **39**
`PXX_PAL_ESP_IDF_TARGET` guards, and every one of them returns
`PAL_ERR_UNSUPPORTED` without IDF — no files, no sockets, no networking. As the
user put it, bare would downgrade an ESP32 to microcontroller level, which
throws away the reason to choose a Wi-Fi SoC in the first place.

So the ordering is:

1. **Windowed caller + callee** — unblocks the xtensa ESP PAL build, and with it
   everything real: networking, peripherals, [[feature-dns-esp-backend]].
   Remember the callee offset is biased by the `entry` frame size (the measured
   gcc reference above reads args 7/8/9 at `sp+32/36/40` after `entry sp,32`).
2. **Call0 callee** — same caller-side spill, offsets read directly at
   `sp+0/4/8`. Needed for the bare profile, which is the niche one.

Both are small once the caller-side spill exists — the caller side is identical
between the two ABIs — so this is a sequencing note, not a scope cut. But if
only one lands first, windowed is the one that turns the S2/S3 hardware the user
actually owns into a usable target.
