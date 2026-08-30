---
slug: feature-a-xtensa-ucontext-pc-sp-offsets
track: A+S
prio: 40
status: backlog
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
