---
slug: bug-a-aarch64-an-aggregate-result-s-destination-is-evaluated-with-the-fp-argument-bank-unsaved
title: "aarch64: the C-ABI call arm saves x0..x7 across the hidden-destination evaluation but not v0..v7, so a float argument to an aggregate-returning C function is unprotected"
track: A
prio: 20
type: bug
status: rejected
created: 2026-09-03
found-by: frankB
owner: frankb-8e
blocked-by: []
summary: "REJECTED 2026-09-22 (frankb-8e) for aarch64 AND arm32, both measured; i386 and x86-64 have the same shape and were NOT looked at. The premise is false by CONSTRUCTION, not merely unreachable. `ir_codegen_aarch64.inc`'s direct C-ABI arm really does save x0..x7 and not v0..v7 around the hidden-destination evaluation, and that asymmetry is CORRECT -- the operand it evaluates in that window, IRC[node], is always `IRAppend(IR_LEA, scratchSym, ...)` over a COMPILER-ALLOCATED scratch symbol at all five sites that build it (inlined in IRAppendCall; `IRBuildHiddenDest` for the CALL_IND and VIRTUAL paths), never the user's destination expression. An aggregate call returns into that scratch and the assignment to the user's lvalue is a separate copy afterwards, so `a nested call inside the destination` is not a shape the IR can hold, and an IR_LEA of a sym lowers to integer address materialisation that touches no v register. x0 needs saving (the LEA clobbers it); d0..d7 do not. MEASURED, not read, and by the route the original probe missed: the 2026-09-03 probe used a BODIED C function, which takes pxx's internal convention and never reaches this arm -- with an EXTERNAL of the reaching shape (`extern struct D2 mk(double,double)`, destination `v[idx()]`) the arm IS reached (differential on the `stp x0,x1,[sp,#-16]!` signature instruction: 1 with the call, 0 without), d0/d1 are demonstrably live and unsaved across it, and the window still holds only ldr/add/mov because the nested idx() call is hoisted above the fmovs. Population: two destination shapes (nested call, float computation), aarch64, compiler sha 06255ab1878c7061. The comment at the site now states the mechanism instead of the gap."
---

# The site

`compiler/ir_codegen_aarch64.inc`, the `ABIRetViaHiddenDestProc(procIdx)` block
of the direct C-ABI call arm:

```
EmitI32($A9BF07E0);              { stp x0, x1, [sp, #-16]! }
... x2/x3, x4/x5, x6/x7 ...
IREmitNodeAarch64(IRC[node]);    { x0 = hidden destination }
EmitI32($AA0003E8);              { mov x8, x0 }
... ldp back ...
```

Eight GP registers saved, no FP registers saved.

# Why it got wider on 2026-09-03 and still is not reachable

Until `bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero`
closed, only a NAMED float parameter of a cdecl call put anything in v0..v7 on
this arm. Now a variadic float tail does too, so the set of calls holding live
FP argument registers across this evaluation is strictly larger.

It is still empty in practice. The arm runs for `ProcExternal[procIdx] or
CProcUsesCAbi(procIdx)`, and `CProcUsesCAbi` is false in C program mode, so a
bodied C function does not reach it. What would reach it is an EXTERNAL, or a
Pascal-mode C prototype, that

- returns a record/aggregate by value (so `ABIRetViaHiddenDestProc` is true), AND
- takes a float or double argument, AND
- is called with a destination expression that clobbers a d register — a nested
  call, or a float computation.

No libc function has the first two together, which is also why the equivalent
x86-64 arm has never been caught by this.

# The fix, when something can exercise it

Save d0..d7 alongside x0..x7. The `str d(n), [x9, #imm]` / `ldr` encodings
already exist in `cparser.inc`'s aarch64 variadic-save prologue (`$FD00xxxx` /
`$FD40xxxx`, Rn=31 for sp), so it needs no new instruction forms — 8 stores, a
64-byte `sub sp`, and the matching restore before the call, symmetric so sp is
back on the outgoing stack-argument block at the call.

**Do not land it without a program that fails first.** The value of this ticket
is the shape, not the patch.

## REJECTED 2026-09-22 (frankb-8e) — the operand cannot be what the ticket says it is

Reopened by frankuser's hypothesis that this ticket shares territory with the
untested by-value-aggregate gap on
[[feature-a-object-output-for-arm32-and-aarch64]]. It does share the territory.
It does not share a defect.

### The route the original probe missed

The ticket's own probe note says `v[idx()] = mk(1.5, 2.25)` was "correct on
native and aarch64, **because in C mode `mk` never takes this arm at all**".
That is an accurate description of a probe that did not reach the subject. The
arm runs for `ProcExternal[procIdx] or CProcUsesCAbi(procIdx)`, so the way to
reach it is to declare `mk` **external** and never define it — which needs no
linker, because the question is what is EMITTED.

Differential on the arm's signature instruction `a9bf07e0`
(`stp x0, x1, [sp, #-16]!`, `ir_codegen_aarch64.inc`):

| program | count |
| --- | --- |
| `extern struct D2 mk(double,double)`, `v[idx()] = mk(1.5,2.25)` | **1** |
| same translation unit with the call removed | **0** |

Emitted *and* reached. `llvm-objdump` at the site confirms the asymmetry the
ticket describes is real and visible: `fmov d1, x9` / `fmov d0, x9` materialise
the arguments at 0x444fe4 and 0x444fec, immediately **above** the four `stp`
that open the window, and no FP register is saved.

### And the hazard still cannot fire, for a reason that is structural

The window's body is three instructions — `ldr x0, <lit>` / `add x0, x29, x0` /
`mov x8, x0`. The `blr x16` that calls `idx()` is at 0x444f88, hoisted well
above the fmovs. A second destination shape, `v[(int)(g * 2.0)]`, emits a
byte-identical window.

Two shapes is a sample, so the mechanism was read rather than inferred from
them. `IRC[node]` on a call with `ABIRetViaHiddenDestProc` true is set at
exactly five places, and every one of them sets it to an `IR_LEA` over a
symbol `AllocVar`/`AllocArray` minted for the purpose:

- `ir.inc`'s `IRAppendCall` inlines it (`scratchAddr := IRAppend(IR_LEA,
  scratchSym, ...)`, then `IRAppend(IR_CALL, procIdx, firstArg, scratchAddr...)`)
  — this is the direct arm, the one under discussion;
- `IRBuildHiddenDest` returns the same shape for the three `IR_CALL_IND` sites
  and the `VIRTUAL_CALL` site, which store it in `IRCallDest[]`.

The aggregate is returned into that scratch; the assignment to the user's
lvalue is a **separate copy emitted afterwards**. So the destination expression
never appears in this window at all, and "a nested call inside it" is not a
state the IR can represent. An `IR_LEA` of a sym lowers on aarch64 to a literal
load plus an `add` against x29 — integer only. `x0` genuinely needs the save
(the `add` clobbers it); `d0..d7` genuinely do not.

### What was actually wrong, and what it cost

A code/comment disagreement, decided the way CLAUDE.md requires rather than by
matching one to the other: the **comment** was wrong, and it had been wrong
since the C-ABI gate flipped. It described the operand as a user expression,
which made a correct save look like half a save, which produced this ticket and
nineteen days of a standing instruction to "save d0..d7 alongside x0..x7" —
eight stores, a 64-byte `sub sp`, and a matching restore, on every
aggregate-returning C-ABI call, buying nothing. The comment now states the
mechanism and cites this rejection.

The ticket's closing instruction was right and is what stopped the patch
landing: *"Do not land it without a program that fails first."*

### arm32, measured rather than caveated — and it fails to have the bug for a SECOND reason

This section first shipped saying arm32 was unmeasured. frankuser's objection
was the summary rule — `REJECTED` reads as a disposition about the CONSTRUCT
and this one was about a TARGET — and measuring was cheaper than scoping the
sentence.

The same program at `--target=arm32` emits the twin arm
(`push {r0-r3}` / `e92d000f`: 1 with the call, 0 without). Its window body is
`ldr r0,[pc]` / `add r0,r11,r0` / `mov r12,r0` — the same `IR_LEA` shape, so
reason (2) below carries over unchanged. But arm32 never had the exposure in
the first place: pxx marshals its arguments as WORDS under the base AAPCS,
doubles included, so both doubles arrive through `ldr r0,[sp]` … `ldr r3,[sp,#0xc]`
and `push {r0-r3}` covers **every** argument. The `vmov d0, r0, r1` that
retrieves the double RESULT is the confirming tell: values cross this boundary
in core registers.

So the two targets are safe for different reasons, and only one of them
generalises:

| | why the FP bank is not at risk | target-independent? |
| --- | --- | --- |
| aarch64 | the window holds only an `IR_LEA` of a compiler scratch sym | **yes** |
| arm32 | FP arguments are not in FP registers at all under base AAPCS | no |

Both sites now say so in their own comments, because the aarch64 one sat
mis-described for nineteen days and the arm32 one is the obvious next place to
ask the same question.

### Population, so nobody inherits this without its denominator

Two destination shapes (`v[idx()]`, `v[(int)(g*2.0)]`), targets aarch64 and
arm32, `--system-libs=c`, compiler sha `06255ab1878c7061`. The **mechanism** is
read from all five `IRC`-construction sites and is not limited to those two
shapes or those two targets; the **disassembly** is. i386 and x86-64 have arms
of the same shape and were not looked at — the provenance argument covers them,
the convention argument does not.

### What would reopen it

An `IRC` on an `ABIRetViaHiddenDestProc` call that is not an `IR_LEA` of a
compiler-allocated scratch sym — i.e. a sixth construction site, or a change to
one of the five that lets a user expression through. Grep for
`IRBuildHiddenDest` and for `IRCallDest[` before assuming the five are still
five.
