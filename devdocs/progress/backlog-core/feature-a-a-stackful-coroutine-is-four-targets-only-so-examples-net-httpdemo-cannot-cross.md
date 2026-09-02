---
slug: feature-a-a-stackful-coroutine-is-four-targets-only-so-examples-net-httpdemo-cannot-cross
track: A
prio: 45
type: feature
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "examples/net/httpdemo builds and matches the x86-64 oracle on i386, arm32 and aarch64 and REFUSES on riscv32 and xtensa: 'coroutines are not implemented for target riscv32'. Three pieces are missing, not one -- the CoSwitch stub in coroutine_emit.inc, the IR_COSWITCH lowering in each backend, and scheduler.pas's per-target initial frame plus epoll syscall numbers, which are written out for exactly four CPUs. xtensa is the harder half: a windowed-ABI stack switch has to spill the register window first, which the other four ABIs do not have to think about."
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
