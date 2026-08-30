---
track: A+O
prio: 55
type: perf
blocked-by: []
summary: "`x div 2^k` / `x mod 2^k` are strength-reduced only at OptLevel >= 3, but -O2 is the default that the compiler and every program it emits are actually built at, so the idiv ships everywhere. Three such sites in the heap allocator were 11.4% of the compiler's own in-.text samples; they were fixed at the SOURCE, which leaves every other site in the RTL, the libraries and all user code still paying it."
status: done
owner: frank-optimize
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

## 2026-08-31 (frank-optimize) — ALREADY PROMOTED. The missing thing was this ticket's own safety condition

**The promotion landed on 2026-08-27 as `13d4bba0c`** — *"perf(O): promote to
-O2 — div/mod by a constant power of two (pass 1 of 3)"*. The guard in
`compiler/ir_codegen.inc` reads `OptLevel >= 2` and the comment above it is
titled *"-O2 constant-divisor strength reduction"*. The umbrella
[[feature-opt-o3-register-pressure]] already recorded it (*"the `-O2` promotion
is DONE (`13d4bba0c`, `e4fe576eb`, `7767acc60`)"*); this ticket did not get the
message and has been offering promoted work at prio 55 ever since.

**Verified by measurement, not by reading the guard** — a program doing
`x div 8` / `x mod 8`, disassembled:

| | idiv | sar |
| --- | ---: | ---: |
| `-O0` | 53 | 1 |
| `-O2` | 49 | 7 |
| `-O3` | 49 | 7 |

`-O2` and `-O3` are identical and both differ from `-O0`. The pass is live at
the default.

### What was actually missing, and it is the part that mattered

This ticket made **item 3 a CONDITION of promoting**: a differential over
signed dividends — *"the bias sequence is where a power-of-two strength
reduction gets it wrong, and it gets it wrong only for negative dividends —
which almost no test happens to use."*

**That condition was never met.** The nearest test,
`test_div_mod_mixed_signedness`, uses **variable** divisors — and the pass needs
`IRKind[right] = IR_CONST_INT`, so **it never fires in that test at all**. The
pass shipped to the default tier, into every binary the compiler emits, with the
one case it can get wrong uncovered.

**The code is correct.** Differential against FPC 3.2.2, negative dividends
-1/-7/-8/-9/-15/-16/-17/-1023/-1024 over 2/4/8/16/1024, `div` and `mod`, at
ShortInt/SmallInt/LongInt/Int64: **`-O0`, `-O2` and `-O3` all match FPC exactly**.
So this is a missing test, not a bug — but nothing was holding it correct.

### The test, and why it is not vacuous

`test/test_div_mod_negative_dividend_pow2.pas` + `.expected`, wired at
**`-O0`, `-O2` and `-O3` against one expectation** (FPC 3.2.2's output).

- **It fires:** `-O0` emits 85 idiv / 1 sar, `-O2` emits 49 idiv / 55 sar / 54
  shr — 36 divisions reduced.
- **`-O0` is a real control**, not a duplicate run: the guard is `OptLevel >= 2`,
  so `-O0` provably cannot use the pass and must reach the same answers by idiv.
- **Sensitivity verified by deliberate break, not asserted:** deleting the bias
  and leaving a bare `sar rax, k` makes **28 of the 35 lines wrong** — `-1 div 2`
  answers -1 instead of 0, floor instead of truncate. Built to a **scratch**
  path with the good compiler, so `compiler/pascal26` was never written.

### Disposition

Resolved. The promotion is done and now has the coverage its own ticket required
before promoting. `gate.sh quick` GREEN, self-host fixedpoint `3c31befa1704`.

**Not claimed:** the ticket's item 2 asked for a full gate *including cross
targets*, since the transformation is emitted from the shared path. That is
Track T's tier and I have not run it. What I can say is that the three rows
above are x86-64, and the aarch64/arm32/riscv32/i386/xtensa arms of this pass
remain covered only by whatever T's matrix already sweeps.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
