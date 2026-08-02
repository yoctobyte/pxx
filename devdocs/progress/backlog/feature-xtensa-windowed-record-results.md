---
prio: 65  # inherits feature-xtensa-stack-args-over-6-words: last blocker on the xtensa ESP PAL
---

# xtensa windowed: by-value record function results

- **Type:** feature (Track S — ESP campaign; Track A file ownership: xtensa
  codegen / ABI)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-08-02 (surfaced the moment the >6-word arg cap was lifted)

## Problem

A function returning a record by value compiles for `--target=xtensa` under
Call0 but is refused under the windowed ABI:

```
pascal26: error: target xtensa: record function results require Call0
                 (windowed not yet supported)
```

Call0 landed 2026-06-23 ([[feature-riscv32-record-function-results]], xtensa
half in the same session): the caller pushes the hidden destination pointer,
loads it into **a8** just before the call; the prologue stashes a8 into
`ProcAggregateDestSym`; the epilogue `PXXMemMove`s Result into `[dest]` and
returns the pointer in a2. Windowed was deferred with the note that the
call-window rotation has no clean caller->callee hidden-dest register — a8 does
not survive `call8` (it becomes the callee's a0, the return address).

## Impact — this is now the LAST blocker on the xtensa ESP PAL

With the argument-word cap gone (21c963bc6), the windowed PAL object build
gets exactly one error left:

```
--target=xtensa --xtensa-abi=windowed --platform=esp -Fulib/rtl \
  -Fulib/rtl/platform/esp test/lib_platform_esp.pas
  -> pascal26:504: error: ... record function results require Call0 ...
     near: function PalIn6Any
```

Windowed is the profile that matters — bare (Call0) has no IDF, hence no
sockets, no networking, no filesystem (39 `PXX_PAL_ESP_IDF_TARGET` guards
return `PAL_ERR_UNSUPPORTED`). So the S2/S3 hardware the user actually owns
stays blocked on this one item.

## Approach

There IS a clean register: the Xtensa ABI's own answer. gcc passes the
struct-return pointer as an **implicit first argument** — caller's a10 (callee's
a2), with every real argument shifted one word up. That is:

- a register that survives the rotation *by construction* (it is an argument
  register),
- the same convention gcc uses, so a record-returning function stays callable
  across the IDF boundary — worth having even though the PAL's own uses are
  PXX-internal,
- reusing the argument path that now handles overflow words, so a
  hidden-dest + 6-real-word call just spills like any other 7-word call.

Sketch: at a windowed call site with `RetViaHiddenDest`, push the dest as word
0 and shift the args; in the callee prologue, spill incoming word 0 into
`ProcAggregateDestSym` and start the parameter word counter at 1. The epilogue
is unchanged (memmove + return the pointer). Watch the constructor path, which
already treats Self as word 0.

## Acceptance

- `test/test_esp_record_result.pas` runs on esp32s3 **windowed** via
  `tools/esp_run.sh --chip esp32s3` with output identical to the x86-64 oracle
  (it already runs Call0 on both chips in `make test-esp-bare`).
- A record result combined with enough arguments to overflow into the stack
  area works (the hidden dest shifts every word by one).
- `--target=xtensa --xtensa-abi=windowed --platform=esp -Fulib/rtl
  -Fulib/rtl/platform/esp test/lib_platform_esp.pas <obj>` emits an object
  importing the expected `lwip_*` symbols — parity with the riscv32 esp object
  smoke (inherited from [[feature-xtensa-stack-args-over-6-words]]).
- Self-host fixedpoint + `make test-esp-bare` stay green.

## Log

- 2026-08-02 — Opened. Found by [[feature-xtensa-stack-args-over-6-words]]:
  that ticket asserted the 6-word cap was "the first and only error" in the PAL
  build, which was an artifact of the compiler stopping at the first error. The
  cap is now lifted and verified on both ABIs; this is what the build hits next.
