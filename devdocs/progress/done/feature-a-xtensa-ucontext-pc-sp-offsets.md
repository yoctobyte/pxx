---
slug: feature-a-xtensa-ucontext-pc-sp-offsets
track: A+S
prio: 40
owner: frankS
summary: "DONE 2026-09-05. xtensa now has both rows -- UContextPCOffset=20, UContextSPOffset=56 -- so __pxxSigPCPtr/__pxxSigSPPtr are no longer refused and fault-to-raise works on hosted xtensa. MEASURED, not read off a header, with two agreeing sources each, and the probe was validated against riscv32 first and reproduced its documented 160/168 before being pointed at xtensa. Three rows wired in test-core (pc_rewrite, sp_rewrite, stack_overflow_raise), all byte-identical to the x86-64 run under local qemu. Resolved as a PAIR with feature-a-a-signal-runtime-for-HOSTED-xtensa, which was already stale."
status: done
---

# xtensa has no ucontext PC/SP offset, so fault-to-raise is refused there

`UContextPCOffset` / `UContextSPOffset` (`compiler/ir.inc`) carry one measured
row per hosted target and **no xtensa row** — they return -1. So
`__pxxSigPCPtr` and `__pxxSigSPPtr` are refused on hosted xtensa, and with them
the whole fault-to-catchable-raise mechanism: `test_signal_pc_rewrite` and
`test_signal_sp_rewrite` do not compile for the target.

Everything else in the signal family now works there — handler install, delivery,
resume, `si_code`, `si_addr`, `ucontext*`, sigaltstack — as of the ruling
`ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired`.
This is the one remaining gap, and it was left deliberately: `ir.inc` was held by
another agent that evening.

**The guard is keyed on the VALUE, not on an arch list** (`UContextPCOffset < 0`),
which is the whole point — an arch list is exactly what went stale in the ruling
above. Add the two rows and the feature opens by itself; there is no guard to
remember to move, and no second site to keep in sync.

## What to do

Measure, do not read off a header — that is what every other row in those two
functions did, and the method is written into their comments:

- **PC**: fault two ways under `qemu-xtensa` (WRITE `$DEAD0000`, and CALL it),
  dump every ucontext word equal to the sentinel. A word matching in BOTH runs is
  a fault-address field; the one matching ONLY when the fault was a jump is the
  saved PC.
- **SP**: fault from a frame carrying a 4096-byte pad and dump every ucontext word
  within 16K of that pad's address. The stack pointer sits a few bytes from it and
  the FRAME pointer a whole pad away — told apart by their delta, not assumed.
- Both answers must ALSO equal what the kernel's `struct sigcontext` predicts.
  Two independent sources agreeing is the bar the other five rows met; i386's row
  needed a differential on top of that, because two candidate words held the same
  value at fault time and only the resumed-stack observable separated them.

Then wire `test_signal_pc_rewrite` and `test_signal_sp_rewrite` into `test-xtensa`
(both are already differentials on the other five targets).

**One xtensa-specific caution.** The kernel enters the handler with the CALL4
convention, and the dispatch stub masks the window bits off the return address
(`a4 and $3FFFFFFF`) — see the stub's entry comment. Rewriting the saved PC
redirects the *resumed* code, which is a different path from that return; do not
assume the two interact, measure that the redirect lands where it should.

Gate: `make compiler/pascal26` + the two rows above + `tools/gate.sh quick`.
`ir.inc` is shared Track A ground — check nobody else holds it first.


## Resolved 2026-09-05 (frankS) — measured, both sources agreeing

### The answers

| | xtensa | derivation |
| --- | --- | --- |
| `UContextPCOffset` | **20** | `uc_mcontext`(20) + `sc_pc`, which is its FIRST field |
| `UContextSPOffset` | **56** | `uc_mcontext`(20) + 8 leading longs(32) + `sc_a[1]`; a1 IS xtensa's sp under both ABIs |

### How, and the control comes first

**The probe was pointed at riscv32 BEFORE xtensa**, because a probe that has
never produced a known-good answer cannot distinguish a right answer from a
plausible one. Two-fault dump (write `$DEAD0000` vs call it), sentinel-matching
ucontext words:

- riscv32 WRITE `{200}`, CALL `{160, 180, 200}` → call-only `{160, 180}`, and
  **160 is riscv32's documented row.** Method reproduces the known answer.
- xtensa WRITE `{60}`, CALL `{20, 60, 88}` → call-only `{20, 88}`, and **20** is
  where the struct puts `sc_pc`. Two sources agree.

SP by the documented pad method — fault from a frame carrying a 4096-byte pad,
dump every ucontext word within 16K of it:

- riscv32: off **168** at delta −16 (its documented row), frame pointer at 192,
  delta +4096.
- xtensa: off **56** at delta −16 — **the identical signature** — frame pointer
  at 112, delta +4096.

So each number has a measurement and a struct derivation, and the measurement
was calibrated on a target whose answer was already known.

### The differential check, which is the one that can fail

`test_signal_sp_rewrite` is load-bearing here for the reason `UContextSPOffset`'s
own comment gives: **a wrong SP offset does not crash.** It leaves the resumed
proc on the OLD stack, so every value assertion still passes and only
`raiser-ran-on-the-spare-stack=TRUE` separates a correct entry from a plausible
one. That is what settled i386's `REG_ESP` vs `REG_UESP`, where both hold the
same value at fault time.

On xtensa, all three now match the x86-64 run byte for byte (LOCAL QEMU RUN):

- `test_signal_pc_rewrite` → `pc-is-the-fault=TRUE` … `hits=1`
- `test_signal_sp_rewrite` → `raiser-ran-on-the-spare-stack=TRUE`
- `test_stack_overflow_raise` → `caught a stack overflow, hits=1` — the real
  consumer, and the reason the SP half exists at all

All three wired in `test-core`.

### The gate opened by itself, as designed

`pasparser_expr.inc` keys the refusal on the VALUE (`UContextPCOffset < 0`)
rather than on an arch list, with a comment saying *"add the row to
UContextPCOffset and this opens by itself."* It did. No parser change was needed
and none was made — worth recording as a design that paid off, since the
comment's stated reason was that an arch list is exactly what had gone stale
one paragraph above.

### Residual, NOT guessed

`test_signal_siginfo` and `test_signal_num` still do not build for xtensa, for a
reason that is not this ticket: they carry `{$ifdef CPU…}` blocks defining
`SYS_gettid`/`SYS_tkill` and have no xtensa arm. Adding one requires settling a
number the tree explicitly flags as unsettled — `ir_codegen_xtensa.inc` records
getpid/gettid as *"MEASURED ONLY TO A SET: 120, 126 and 127 … do not 'correct'
it to a confident name without a threaded measurement."* A threaded measurement
would settle it. Left for whoever does that, rather than picked from the set.
