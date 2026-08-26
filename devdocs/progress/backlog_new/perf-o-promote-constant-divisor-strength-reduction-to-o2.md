---
track: A+O
prio: 55
type: perf
blocked-by: []
summary: "`x div 2^k` / `x mod 2^k` are strength-reduced only at OptLevel >= 3, but -O2 is the default that the compiler and every program it emits are actually built at, so the idiv ships everywhere. Three such sites in the heap allocator were 11.4% of the compiler's own in-.text samples; they were fixed at the SOURCE, which leaves every other site in the RTL, the libraries and all user code still paying it."
---

# Promote the constant-divisor strength reduction from `-O3` to `-O2`

`compiler/ir_codegen.inc` already implements it, correctly and with the
semantics written out (Pascal `div` truncates toward zero, `mod` takes the sign
of the dividend, so the signed form biases with `sar 63; shr 64-k` before
shifting; unsigned needs neither). It gates on `OptLevel >= 3`.

**The problem is that nothing is built at `-O3`.** `compiler.pas:739` sets
`OptLevel := 2` as the default; `PXXFLAGS` in the Makefile is empty, so the
compiler self-hosts at `-O2`; every library, every test binary and every user
program compiles at `-O2` unless somebody types otherwise. So the pass is
written, tested, documented — and off.

## What it costs, measured

Sampling profile of the real `-O2` compiler (`compiler/pascal26` at
`cd5a3aaf8`, profiled as `-O2 -g` because a bare `-g` silently selects `-O0`)
compiling a zero-byte `.npy`. Three single instructions, all `idiv` by the
literal 8, all in `compiler/builtin/builtinheap.pas`:

```
4.04%  0x40098f   ((size + 7) div 8) * 8    PXXAlloc round-up
3.75%  0x4009d3   Integer(size div 8) - 1   PXXAlloc bin index
3.58%  0x400edb   Integer(sz   div 8) - 1   PXXFreePush bin index
-----
11.4%  of all in-.text samples, on three instructions
```

Each is a ~25-40 cycle `idiv` preceded by `test rcx,rcx; jne` — a runtime
zero-divisor check on a constant that is provably 8. Removing just those three
at the source was **-17% user CPU** on a NilPy compile (`1202429f4`).

That fix was deliberately narrow. Every other `div`-by-power-of-two in
`lib/rtl`, `lib/pcl`, `lib/crtl`, the RTL's own string and container code, and
all user code still emits the idiv.

## Why it was not promoted in the same session

CLAUDE.md: *"New passes land behind `-O3` (a free tier) and promote to `-O2`
per-pass only after the full gate; `-O2` stays the proven default."* The full
gate is Track T's, not a dev worker's, so promoting it is a deliberate call with
a matrix run behind it rather than something to slip in beside a perf fix.

## What promotion needs

1. Change the one `OptLevel >= 3` guard on this pass (and only this pass) to
   `OptLevel >= 2`. It is a local, provable transformation with no cross-
   statement analysis, which is the profile a promotion candidate should have.
2. Full gate at the resulting sha, **including the cross targets** — the
   transformation is emitted from the shared `ir_codegen.inc` path, so aarch64,
   arm32, riscv32, i386 and xtensa all change.
3. A differential over signed dividends specifically: `-1 div 8`, `-7 div 8`,
   `-8 div 8`, `-9 div 8` and the `mod` counterparts, against FPC, at every
   width. The bias sequence is where a power-of-two strength reduction gets it
   wrong, and it gets it wrong only for negative dividends — which almost no
   test happens to use.

## Adjacent, and probably worth the same run

`-O3` for the compiler binary itself measured 4.43-4.80s against `-O2`'s
5.14-5.49s on a zero-byte `.npy` (~12%), most of which was these same idivs.
Once they are folded at `-O2` the gap should mostly close; if it does not, what
is left is `feature-opt-o3-register-pressure`'s territory and belongs there.
