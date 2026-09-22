---
slug: bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss
title: "The signal alt stack is 32,768 bytes of BSS in every image, --no-signals included"
track: A
prio: 15
type: bug
status: new
created: 2026-09-18
owner: ""
summary: "THE SOURCE COMMENT THAT KEPT THIS AN ESP TICKET IS REPAIRED AND THE ESP UMBRELLA EDGE IS CUT (frankh-c0, 2026-09-22). `compiler/defs.inc` still said EnsureSignalBss allocated the alt stack unconditionally, --no-signals included, so a target whose BSS is SRAM paid 32768 bytes in every image -- true when written, false since `16ebf18ce`, and it named a function that no longer holds the allocation. `ir_codegen.inc` carried the SAME stale referent and was found only by grepping the CONSTANT, not the claim. Re-measured at HEAD by halving SIG_ALTSTACK_SIZE and rebuilding, because a plain-vs---no-signals delta of 0 cannot tell \"not allocated\" from \"allocated on both arms\": bare esp32c3 and esp32s3 66808 -> 66808 (delta 0), hosted x86-64 plain 35324 -> 18940 (delta 16384), hosted --no-signals 2532 -> 2532 (delta 0). So it costs an ESP image NOTHING; it was cut from umbrella-an-esp32-image-is-as-small-as-it-can-be, which had been inheriting it to effective 70 and putting it at the top of `next --track A` while its own author had re-ranked it 15. THE SLUG AND TITLE SAY \"unconditional\" AND THAT WORD IS FALSE. What remains is PIECE 2 only, hosted-only tuning of a facility that is genuinely live -- the entry installs SIGINT/SIGTERM by default and the emitter registers the buffer with sigaltstack(2). EARLIER: TWO OF THE THREE PIECES ARE DONE AND THE SRAM CASE -- THE WHOLE REASON THIS RANKED -- IS DISCHARGED. Re-measured 2026-09-19 (frankS). This summary described the alt stack as reserved before the `if NoSignals then Exit` and therefore paid by every image; that stopped being true at `16ebf18ce` on 2026-09-18, the body has recorded it as FIXED forty lines down ever since, and the stale summary went on routing this as a live p60 SRAM bug -- which is the exact misroute \"a ticket's summary MUST be true\" exists to prevent, so it is fixed here rather than appended to. PIECE 1 (conditional on --no-signals): FIXED, `16ebf18ce`. PIECE 3 (LINE_BUF_SIZE, 4096 B of stdin line buffer in a program with no ReadLn): FIXED AND NOBODY RECORDED IT -- `0ab100740`, the same day, as a side effect of a CORRECTNESS fix (\"a long line no longer becomes two\"); PXXLineBuf is a Pointer realloc'd on demand and LINE_BUF_SIZE no longer appears in compiler/** at all, which also retires the twin-spelling hazard CLAUDE.md cites against this pair. PIECE 2 (size the constant per target) is what remains and it is hosted-only tuning: after piece 1 the constant costs nothing where no handler exists. MEASURED, hello world, plain vs --no-signals: BOTH BARE ESP PROFILES PAY ZERO (esp32c3 and esp32s3 bare, 66808 -> 66808, delta 0) because TargetHasSignalRuntime is false where there is no OS to deliver a signal; the six hosted profiles pay 32792 = SIG_ALTSTACK_SIZE + the 24-byte stack_t. THAT ATTRIBUTION IS A DIFFERENTIAL AND NOT A MATCHING NUMBER: halving the constant to 16384 moves the delta to 16408 on x86-64 and xtensa-posix and leaves bare at 0, so the source is that constant rather than something the same size. The body's own floor figures are stale too and are corrected below: x86-64 --no-signals bss is 2532, not 9008, and a bare hello is 66808, not 70936 -- both moved by piece 3. Where the cost still lands, it is hosted BSS, which is zero-filled pages with no file cost and where the runtime does install SIGINT/SIGTERM by default, so the alt stack is genuinely used. Re-ranked 60 -> 15 on that: real, correct, and not worth ranker attention."
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

## FIXED 2026-09-18 (frankS) — piece 1 of the three

`EnsureSignalAltStack` split out of `EnsureSignalBss`, and called from
`EmitSignalRuntimeForTarget` past `if NoSignals then Exit` under
`TargetHasSignalRuntime`. **Reserved iff a runtime is emitted**, one place, so
"reserved" and "emitted" cannot drift — which is what the four separate
per-arch-allocation bugs in `EnsureSignalBss`'s own history were.

The 56 bytes of SLOTS stay unconditional, and the ticket was right that the
existing comment's argument covers exactly those: the signal-info builtins read
them whether or not a handler exists, and a 0 offset would address `BSS[0]`.
Nothing addresses the alt stack except the runtime that installs it.

**Measured, both directions:**

| build | bss before | bss after | delta |
| --- | ---: | ---: | ---: |
| x86-64 hello, `--no-signals` | 41,800 | **9,008** | **−32,792** |
| x86-64 hello, signals ON | 41,800 | 41,800 | 0 (control) |
| esp32c3 `--esp-profile=bare` | 103,728 | **70,936** | **−32,792** |
| esp32s3 `--esp-profile=bare` | 103,728 | **70,936** | **−32,792** |

−32,792 is exactly `SIG_ALTSTACK_SIZE` + the 24-byte `stack_t`. **Every ESP
image gets 32 KB of SRAM back** — 8% of a C3 — because `TargetHasSignalRuntime`
is False on the ESP platform, so the reservation never had a reader there.

**Positive control, the one this ticket specified.** `test_signal_altstack`
prints `handler-off-faulting-stack=TRUE`: a handler installed, the stack
faulted, the handler entered on the alt stack. Also green:
`test_signal_bss_alias` (`hit=1 argv-intact=TRUE` — the guard against exactly
the `BSS[0]` aliasing this split could have reintroduced),
`test_setsignalhandler_call`, `test_signal_handler_callback_b336`,
`test_signal_default_revert_b336` (rc=143, correct), and
`test_cross_signal_runtime_predicate`. Hosted hello still prints `hello`.

## Still open — pieces 2 and 3

2. **Size it per target.** 32768 is chosen against AVX-512's signal frame.
   riscv32 and arm32 have no 512-bit register file and their frames are a
   fraction of it. This fix makes the constant cost nothing where no handler
   exists; it does not make it the right size where one does.
3. **`LINE_BUF_SIZE`.** 4,096 bytes of stdin line buffer in a program with no
   `ReadLn`. Now the largest single item in the floor: after this fix the
   x86-64 `--no-signals` bss is 9,008, of which the TLS main block is 4,240 and
   this is 4,096 — together **93%** of what remains.

## Note 2026-09-18 — where the ESP bss actually goes, now that this is fixed

After this fix a bare esp32c3/esp32s3 hello is `bss=70936`, and **65,536 of it
is one buffer**: `EspArena` in `compiler/builtin/builtinheap.pas`, sized by
`HEAP_ARENA`. Established by differential, because a subtraction cannot name a
constant: halving `SocNilPyArenaSize` (`defs.inc`, the compile-time NilPy
reservation) left bss at 70,936 **unchanged**, while halving `HEAP_ARENA`
moved it to 38,168.

`SocNilPyArenaSize` was called `SocBareArenaSize` until today and that name cost
a seat a wrong diagnosis — two things called "the arena", both 64 KiB, and a
grep reaches the compiler-side one first. Renamed, cross-referenced at both
sites.

## RE-MEASURED 2026-09-19 (frankS) — the floor figures above are stale, and piece 3 is done

Arrived here as a p70-shaped lead from a peer, who was explicit that it was a
lead to check rather than a conclusion. Two of the three things the summary
said did not match the tree.

**Piece 3 closed by events and nobody wrote it down.** `0ab100740`, 2026-09-18,
*"one growable readln line buffer — a long line no longer becomes two"*. It was
a correctness fix; the 4,096 bytes left the floor as a side effect.
`PXXLineBuf` is a `Pointer` grown by `PXXRealloc`, and `LINE_BUF_SIZE` no
longer appears anywhere under `compiler/**`.

**The floor, re-measured.** Identical for `begin end.` and for a `WriteLn`
hello, so this is the floor and not the program:

| profile | plain | `--no-signals` | delta |
| --- | --- | --- | --- |
| x86-64 | 35324 | 2532 | 32792 |
| i386 / arm32 / riscv32-posix / xtensa-posix | 34108 | 1316 | 32792 |
| aarch64 | 34156 | 1364 | 32792 |
| **esp32c3-bare** | **66808** | **66808** | **0** |
| **esp32s3-bare** | **66808** | **66808** | **0** |

The body above records 9,008 for the x86-64 `--no-signals` floor and 70,936 for
a bare hello. Both predate piece 3.

**The attribution is a differential, not a matching number.** 32,792 equals
`SIG_ALTSTACK_SIZE` + 24 exactly, which is the shape that names a quantity and
never a source — the `SocBareArenaSize`/`HEAP_ARENA` trap this ticket's own
`Note 2026-09-18` was written about. So the constant was changed rather than
read: at `SIG_ALTSTACK_SIZE = 16384` the delta becomes **16408** on x86-64 and
xtensa-posix, and bare stays **0**. Reverted; the compiler rebuilt to the same
sha it started at (`f4282f49e62e`).

**Why bare pays nothing.** `EnsureSignalBss` runs unconditionally, and only
`EnsureSignalAltStack` sits behind both `NoSignals` and
`TargetHasSignalRuntime` — which asks the platform, and there is no OS on bare
to deliver a signal. So the delta is structurally the alt stack alone, which is
why the arithmetic comes out clean.

**What this means for the ranking.** The SRAM argument was the reason this sat
at p60, and it is discharged: the ESP profiles pay zero. What remains is piece
2, sizing the constant per target, and it bites only where a handler can exist
— hosted, where BSS is zero-filled pages with no file cost and where the
runtime installs SIGINT/SIGTERM by default, so the alt stack is used rather
than merely reserved. Re-ranked to 15.
