---
slug: feature-a-a-stackful-coroutine-is-four-targets-only-so-examples-net-httpdemo-cannot-cross
track: A
prio: 45
type: feature
status: working
created: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "riscv32 is DONE -- examples/net/httpdemo builds and runs there with output byte-identical to the x86-64 oracle, and i386/arm32/aarch64 are unchanged. XTENSA REMAINS, and it is the hard half: under the windowed ABI the callee-saved state lives in a rotating register window rather than on the stack the way CoSwitch assumes, so a stack switch has to spill the window first. riscv32 took FOUR pieces, not the three this ticket predicted -- the CoSwitch stub, the IR_COSWITCH lowering, scheduler.pas's initial frame and epoll syscall numbers, AND atomic codegen, which riscv32 refused in user mode because its only primitive was the ESP arm's machine-mode interrupt mask."
---

# A stackful coroutine is four targets only, so `examples/net/httpdemo` cannot cross

Named by attempting the target (`umbrella-cross-target-codegen-is-correct`,
2026-09-02, at `c2e9bbafd`):

```
httpdemo | i386:ok arm32:ok riscv32:BUILD aarch64:ok xtensa:BUILD
```

Both refusals are the same line, and it is a true statement rather than an
internal-node leak:

```
pascal26:651: error: coroutines are not implemented for target riscv32
pascal26:651: error: coroutines are not implemented for target xtensa
```

`httpdemo` is a loopback HTTP/1.1 server coroutine and a client coroutine on one
thread over the epoll reactor — `uses scheduler, asyncnet, http`. It is the
real program this blocks; generators (`; generator;`) are the other consumer,
and `examples/chess` only crosses today because it was moved to the STACKLESS
spelling (`995b1daef`), which is a different mechanism and not a substitute.

## Three pieces, and only the first one is obvious

1. **`coroutine_emit.inc`** — the `CoSwitch` stub. x86-64, aarch64 and arm32
   each have one; the `else` arm raises the refusal above. arm32's is ~15
   instructions (push callee-saved + lr, thread `BSS_EXC_TOP` through the swap,
   store sp to `[r0]`, load from `[r1]`, restore) and riscv32's would be its
   near-twin over `s0`-`s11`/`ra`.
2. **`IR_COSWITCH` in the backend.** Its own comment says why both halves must
   land together: today a program that reaches a missing stub is *masked* by the
   backend refusing the node, and *"give riscv32 one without adding a stub arm
   here and the downstream guard disappears, leaving exactly the
   call-to-address-zero this else now prevents."*
3. **`lib/rtl/scheduler.pas`** — the piece a reader of the refusal would not
   expect. Its initial-frame layout, its `TEpollEvent` shape and its syscall
   numbers are spelled out under `{$ifdef CPUX86_64}`, `CPU_I386`, `CPU_AARCH64`
   and `CPU_ARM32` — **four arms, no riscv32 or xtensa**, so the unit compiles to
   nothing on those two even once the compiler stops refusing.
   `lib/rtl/coroutine.pas` (the generator runtime) is worse: the WHOLE unit is
   inside one `{$ifdef CPUX86_64}`, including `CoAlloc`, whose initial frame is
   written in 8-byte words against the x86-64 register set. A 32-bit target
   needs its own, not a widened one.

## xtensa is not riscv32's twin here

riscv32 is a mechanical port of the arm32 shape. **xtensa is the hard one:**
under the windowed ABI the callee-saved state lives in a rotating register
window rather than on the stack the way `CoSwitch` assumes, so a stack switch
has to spill the window first. Do riscv32 first and measure; do not size the two
together.

## Not a regression

Nothing here used to work. The four supported targets are the four somebody
wrote, and this ticket is the fifth and sixth.

## riscv32: done, and the fourth piece the ticket did not predict

Landed 2026-09-02. `examples/net/httpdemo` on riscv32 is **byte-identical to the
x86-64 oracle** — the server coroutine and the client coroutine both run, over
epoll, on one thread. i386, arm32 and aarch64 re-checked at the same tree and
still byte-identical, so nothing here reached them.

The three pieces above were all needed and all sufficient *in shape*:

1. `compiler/coroutine_emit.inc` — a 16-byte frame, three live slots
   (`exc_top`@0, `s0`@4, `ra`@8, one word of pad so sp stays 16-byte aligned per
   the psABI). **Three slots, not twelve**, because riscv32 codegen never
   allocates `s1`-`s11` — only `s0`, as the frame pointer. That is a property of
   our register allocator, so it is written down at the stub: a future allocator
   that starts using `s1`+ must widen this frame, and nothing else will notice.
2. `compiler/ir_codegen_riscv32.inc` — the `IR_COSWITCH` arm, landed in the same
   commit as the stub for the reason the file's own comment gives.
3. `lib/rtl/scheduler.pas` — `CPU_RISCV32` arms. Note the syscall numbers are
   **aarch64's, not arm32's**: riscv32 is an asm-generic port, and reaching for
   the other 32-bit arm's table is the mistake this shape invites.

### The fourth: atomics, found only by building it

`scheduler.pas` takes a registration lock, so the next refusal after the
coroutine one was `target riscv32: atomics need machine-mode CSR access
(mstatus)`. True for the ESP32-C3 (RV32IMC — genuinely no A extension), and the
refusal had generalised from that one part to every rv32 core. Hosted rv32 has
the A extension, so:

- `compiler/rv32enc.inc` gained `rv32_amoswap_w`, `rv32_amoadd_w`, `rv32_lr_w`,
  `rv32_sc_w` over a shared `rv32_amo_w`, with `funct7 = (funct5 shl 2) or
  (aq shl 1) or rl`. **Byte-verified against `clang --target=riscv32
  -march=rv32ima`**, not derived: an encoder that is only reasoned out
  assembles to *something*, and something is not the instruction.
- The hosted emission path replaces the flat `TargetPlatform <> PLATFORM_ESP`
  refusal. `ATOMIC_ADD` and `ATOMIC_XCHG` are single AMOs; **CAS needs the
  LR/SC pair**, because no atomic-memory-op encodes "store only if it still
  equals expected". The ESP arm is untouched and still masks interrupts.

`test/test_riscv32_hosted_atomics.pas` covers all three, and asserts the CAS
*mismatch* case does not store — the row that separates a real CAS from an
unconditional swap.

## Remaining: xtensa

Everything above is riscv32-only. xtensa still refuses, and the windowed-ABI
window-spill described above is unchanged and unstarted. `lib/rtl/coroutine.pas`
(the generator runtime, whole unit inside `{$ifdef CPUX86_64}`) is also still
untouched — this work went through the scheduler path only, so generators cross
on no 32-bit target yet.
