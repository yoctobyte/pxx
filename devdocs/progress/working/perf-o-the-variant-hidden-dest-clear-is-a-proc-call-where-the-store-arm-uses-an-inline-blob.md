---
type: perf
track: A
prio: 35
status: working
slug: perf-o-the-variant-hidden-dest-clear-is-a-proc-call-where-the-store-arm-uses-an-inline-blob
summary: "THE TITLE IS WRONG IN THE DIRECTION THAT INFLATES THE PRIZE AND THE FIX IS SMALLER THAN THE BODY CLAIMS (frankh-c0, 2026-09-22, re-read at HEAD). The store arm does NOT use an inline blob -- the blob is OUT OF LINE and reached by a call, and it exists because the inline spelling cost ~42% of output on a zero-byte .npy and ~99% of the text assembler's traffic. BOTH PATHS CALL. The real asymmetry is that IRBuildHiddenDest calls the PORTABLE Pascal proc (arg node + frame) while IR_VAR_STORE calls the TARGET'S OWN blob (no arg node, no frame, preserves rax) -- and a census of every backend shows ONLY x86-64 has a divergent fast spelling: four backends already call the portable proc from both paths and are uniform, aarch64 has its own helper. So the body's \"every backend needs the arm\" is true of the new-IR-kind approach and NOT of the asymmetry named here, which is x86-64-local. The saving is argument marshalling plus a frame, not a whole call. COST EVIDENCE IS SYNTHETIC AND SEVEN DAYS OLD (+14%/+8% against a binary that no longer exists) and the ticket's own retirement condition asks for a real program: lekkerzeilen-7a has been asked for dispatch as a share of a ROOFS frame. THE CARRIER IS PER CALL SITE, NOT PER CALL -- re-derived at HEAD 2026-09-22 with PXXDBG=a.ir: two k.m(t) sites mint two DISTINCT unnamed carriers (557, 558), each cleared by a call before its hidden-dest virtual_call, so a loop over one site reuses ONE slot. The dynamic cost is per CALL and a release sweep's population is per SITE; multiplying a per-slot win by call frequency mixes them. NOT measured: whether the carrier still owns a reference after the var_store -- that is perf-a's question. THE TIMING HALF IS DEFERRED ON PURPOSE -- load was 14.35, and 7a measured the same binary/scene/pin at 530ms quiet vs 624ms while peers merely COMPILED, with CPython moving 66% against pxx 18%, so contention is DIFFERENTIAL and a ratio is unbounded until both arms run interleaved on a quiet box."
owner: frankh-c0
blocked-by: [task-e-decompose-a-lekkerzeilen-roofs-frame-so-two-perf-tickets-stop-guessing-at-their-own-prize]
---

# The variant hidden-dest clear is a full proc call where IR_VAR_STORE uses an inline blob

`IRBuildHiddenDest` and `IRAppendCall` both clear the variant scratch slot
before a hidden-dest call by emitting `IR_CALL` to `PXXVarClear` with an
`IR_ARG` holding an `IR_LEA` — a real call with argument setup.

`IR_VAR_STORE` and `IR_VAR_BOX` clear their destination with
`IREmitNode(IRA[node]); EmitVariantClear;` — the address in rax and the
`VariantClearBlobAddr` blob, which **preserves rax** (`defs.inc`). No call
frame, no argument node.

The two do the same thing by different means, and the expensive one is on the
hot path: every NilPy method call returns a Variant, so every method call pays
it.

## MEASURED COST, 2026-09-15, interleaved min-of-5 against `pascal26_BOTHFIX`

| program | old | new | |
|---|---|---|---|
| 6M bare method calls, no other work | 1.96s | 2.23s | **+14%** |
| method-heavy with allocation per iteration | 0.84s | 0.91s | **+8%** |

The clear itself is correct and is NOT the thing to remove — it fixes an
unbounded leak (`bug-n-a-method-result-that-rides-the-variant-carrier-leaks-a-reference-per-call`,
closed 2026-09-15). This ticket is only about how it is spelled.

The worst case in the table is the honest one to quote for a dispatch-bound
program, and the 8% row is closer to what real code sees.

## WHAT IT WOULD TAKE, AND WHY IT IS NOT A ONE-LINER

There is no IR kind for "release the variant payload at this address". The
store arms reach `EmitVariantClear` from inside their own codegen arm, where
the address is already in the register. A shared spelling needs either a new
IR kind — and `IRCallDest` is consumed per backend, so every backend needs the
arm — or the clear folded into the existing hidden-dest emission each backend
already does.

**Do not start this by changing one backend.** `gate.sh quick`'s backend-parity
row exists to catch exactly that, and the leak fix it would be optimising was
written in the IR precisely so all six inherit it.

## WHAT WOULD RETIRE THIS TICKET WITHOUT WORK

A measurement showing the clear is cheap relative to the dispatch it rides on
in a REAL program rather than a microbenchmark. Both rows above are synthetic,
and neither says what a demo pays. `lekkerzeilen`'s own leak instrument reports
CPU percentages per leg and would answer it as a side effect.

## 2026-09-22 (frankh-c0) — THE PREMISE, RE-READ AT HEAD. The title is wrong in the direction that inflates the prize.

Checked before planning a fix, because the cost rows above are from 2026-09-15
against a binary (`pascal26_BOTHFIX`) that no longer exists.

**"the store arm uses an inline blob" IS NOT WHAT THE CODE DOES.** The blob is
**out of line and reached by a `call`**, and it exists precisely because the
inline spelling was too expensive: `EmitVariantClear` used to splice its
~96-byte body at every site, which on a ZERO-BYTE `.npy` is 9,859 sites,
~946 KB, **~42% of the whole 2.23 MB output** — and 138,026 of the compiler's
139,657 `AsmTextLine` calls, ~99% of the text assembler's traffic
(`EmitVariantBlobs` header, `ir_codegen.inc`).

So this ticket is **not** call-versus-inline. Both paths call. The real
difference is narrower:

| path | what it emits |
| --- | --- |
| `IRBuildHiddenDest` / `IRAppendCall` | `IR_CALL(PXXVarClear, IR_ARG(IR_LEA(scratch)))` — the **portable Pascal proc**, with an argument node and a frame |
| `IR_VAR_STORE` / `IR_VAR_BOX` | address already in rax, `call VariantClearBlobAddr` — **no arg node, no frame**, and the blob preserves rax |

**THE SHARPER STATEMENT, WHICH IS ALSO A SMALLER FIX THAN THIS TICKET CLAIMS:**
on x86-64 the hidden-dest path takes the **portable** route while the store path
takes the **target's own fast** one. `builtinheap.pas` says it outright —
*"This is the PORTABLE half of a pair: x86-64 emits the same test inline
(EmitVariantClear) and every other target calls here."*

Census of every backend at HEAD, `VariantClearBlobAddr` / `'PXXVarClear'` /
`EmitVariantClear`:

```
ir_codegen.inc          (x86-64)  2  5  13
ir_codegen_aarch64.inc            0  0   7
ir_codegen386.inc                 0  1   0
ir_codegen_arm32.inc              0  1   0
ir_codegen_riscv32.inc            0  1   0
ir_codegen_xtensa.inc             0  1   0
ir_codegen_wasm32.inc             0  3   0
```

**Only x86-64 has a divergent fast spelling.** Four backends already call the
portable proc from BOTH paths and are uniform; aarch64 has its own helper. So
"every backend needs the arm" is true of the new-IR-kind approach and **not of
the asymmetry this ticket actually names** — that one is x86-64-local, where two
spellings already coexist, and the semantics are identical either way.

**The saving is therefore argument marshalling plus a Pascal frame per
hidden-dest variant call, not a whole call.** Whatever the retirement
measurement comes back as, the prize is smaller than the title implies, and the
title should be fixed whether or not the ticket survives.

## Status: the timing half is DEFERRED, deliberately

Load average was **14.35** when this was written. lekkerzeilen-7a measured the
same binary, same scene, same pin at **530 ms on a quiet box and 624 ms while
peers were merely COMPILING** — no second demo, no GPU contention — and the
CPython arm moved 66% where pxx moved 18%, so the **ratio** went 14.0x to 19.7x.
**Contention is differential, so a ratio is unbounded until both arms are
measured in one interleaved session on a quiet box.** No timing row is worth
taking here until that holds.

Asked 7a for one row instead (dispatch as a share of a **roofs** frame). Its
asymmetry argument is why that one run can settle this: the flag
`PyModuleHasComputedGetattr` is TRUE today, so every method pays boxing — **if
dispatch is small in the EXPENSIVE regime it is small in the cheap one too, so
the measurement can retire this ticket but cannot confirm it.**

## 2026-09-22 (frankh-c0) — the body's NilPy claim, RE-DERIVED at HEAD, and the denominator it hides

Line 23 says *"every NilPy method call returns a Variant, so every method call
pays it."* My re-read section above corrected the blob claim and the six-arm
claim and **never touched this one**, so it was still inherited when frankz-e5
relayed it to frankb-8e as a re-measured fact of mine. Measured now.

`PXXDBG=a.ir:driver` on a NilPy class with two `k.m(t)` call sites, at HEAD:

```
16: lea a=557 [sym=]        <- unnamed compiler-minted carrier
17: arg a=16
18: call a=64 b=17          <- the clear
19: lea a=557 [sym=]
20: virtual_call ival=4     <- hidden dest
21: var_store a=4 b=20

34: lea a=558 [sym=]        <- a DIFFERENT unnamed carrier
36: call a=64 b=35
38: virtual_call ival=4
```

**The claim is TRUE and is now re-derived rather than inherited.** Each method
call site mints an unnamed carrier and emits a clear call on it before the
hidden-dest call; the `lea/arg/call` then `lea/virtual_call` shape is what
`ir_codegen.inc` documents for this path, and the carriers are `[sym=]`.

### THE CARRIER IS PER CALL SITE, NOT PER CALL — and that is two different denominators

557 and 558 are distinct symbols for two **static** sites. A loop calling one
method a million times reuses **one** slot. So:

- the **dynamic** cost (what this ticket is about) is per CALL;
- the **swept population** (what a release-sweep analysis counts) is per SITE.

Anything that sizes a prize by multiplying a per-slot win by call frequency is
mixing them, which is the umbrella's own do-not-multiply warning reached
through this subsystem rather than its own. Recorded here because the two
numbers are both about "variant carrier slots" and read as interchangeable.

### What is measured here and what is NOT

Measured: where the carrier is minted, that it is unnamed, that it is cleared
by a call before the hidden-dest call, that it is distinct per site, and that
it is `var_store`d into the user local afterwards.

**NOT measured: whether the carrier still owns a reference after that store** —
whether `var_store` of a variant retains or moves. That is the fact that
decides whether a release on these slots can be SKIPPED rather than merely made
cheaper, it is `perf-a`'s question and not this ticket's, and nothing here may
be read as answering it.
