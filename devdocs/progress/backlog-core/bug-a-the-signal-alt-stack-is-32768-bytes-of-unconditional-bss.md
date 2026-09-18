---
slug: bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss
title: "The signal alt stack is 32,768 bytes of BSS in every image, --no-signals included"
track: A
prio: 60
type: bug
status: new
created: 2026-09-18
owner: ""
summary: "`EnsureSignalBss` (ir_codegen.inc:1307) reserves SIG_ALTSTACK_SIZE = 32768 unconditionally, and `ir_codegen.inc:1445` calls it BEFORE the `if NoSignals then Exit`. defs.inc justified it as \"zero-filled BSS with no file cost\" — true of a hosted target, and false wherever BSS is SRAM. Measured 2026-09-18: an x86-64 hello world at its 195-byte code floor still carries 41,800 bytes of bss, of which 32,768 is this one constant — 78%. The other two large items are the TLS main block (4,240) and the readln stdin line buffer (4,096, LINE_BUF_SIZE), neither of which a program that does not read stdin will ever touch. On an ESP32-C3 with ~400 KB usable SRAM this is 8% of the chip for a facility the program opted out of."
---

# The floor's bss, in full

x86-64, `WriteLn('hello')`, `-uPXX_MANAGED_STRING --no-signals`, code 195 B:

| item | bytes | share |
| --- | ---: | ---: |
| signal alt stack (`SIG_ALTSTACK_SIZE`) | 32,768 | 78.4% |
| TLS main block (`TLS_BLOCK_SIZE` + 16) | 4,240 | 10.1% |
| readln line buffer (`LINE_BUF_SIZE`) | 4,096 | 9.8% |
| heap ptrs, locks, 64-slot hook table, scratch | 696 | 1.7% |
| **total** | **41,800** | |

`--no-signals` changes none of it. `--dce` changes none of it.

## Why it is allocated under --no-signals

`EnsureSignalBss`'s own comment gives the reason and it is sound as far as it
goes: the signal-info builtins lower to `BSS_SIG_CODE/_ADDR/_CTX/_NUM`, and a 0
offset there would read `BSS[0]`. That argument covers the **56 bytes of slots**.
It does not cover the 32,768-byte alt stack, which no builtin addresses — the
comment extends the same reasoning to it on the grounds that making it
conditional "would put a condition on a function whose whole contract is
idempotent, call it whenever".

## Fix shape

Three independent pieces, smallest first:

1. **Make the alt stack conditional on `NoSignals`.** The slots stay
   unconditional; only the 32 KB moves. Keep `EnsureSignalBss` idempotent by
   splitting the alt-stack reservation into its own idempotent call.
2. **Size it per target.** 32768 is chosen against AVX-512's signal frame. An
   ESP32-C3 has no AVX-512 and no 512-bit register file; riscv32's frame is a
   fraction of that.
3. **Make `LINE_BUF_SIZE` demand-allocated or opt-out.** A program with no
   `ReadLn` pays 4,096 bytes for a stdin line buffer.

## Positive control

Any fix must keep a program that *installs a handler and faults on its own
stack* working — that is what the alt stack is for. `test/` has the signal
fixtures; run them with and without `--no-signals` and assert the alt stack is
present in exactly one.
