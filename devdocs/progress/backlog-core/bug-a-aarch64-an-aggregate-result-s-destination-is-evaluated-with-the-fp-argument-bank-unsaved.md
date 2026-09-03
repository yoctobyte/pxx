---
slug: bug-a-aarch64-an-aggregate-result-s-destination-is-evaluated-with-the-fp-argument-bank-unsaved
title: "aarch64: the C-ABI call arm saves x0..x7 across the hidden-destination evaluation but not v0..v7, so a float argument to an aggregate-returning C function is unprotected"
track: A
prio: 20
type: bug
status: open
created: 2026-09-03
found-by: frankB
owner:
blocked-by: []
summary: "`ir_codegen_aarch64.inc`'s direct C-ABI arm loads the arguments, then evaluates the AAPCS indirect-result destination `IRC[node]` (which may contain a nested call) with x0..x7 pushed and popped around it -- and v0..v7 NOT pushed. Its own comment already says the args are in `x0..x7 and v0..v7`, so the code and the comment disagree and the comment is the correct half. NOT REPRODUCIBLE TODAY, which is why it is a note and not a fix: this arm serves EXTERNALS and Pascal-mode C prototypes only (a bodied C function in C mode takes pxx's internal convention -- `CProcUsesCAbi`), and reaching it needs a function that returns an aggregate BY VALUE and takes a floating-point argument, which no libc entry point does. Probed 2026-09-03 with a struct-returning C function whose destination expression contains a call (`v[idx()] = mk(1.5, 2.25)`): correct on native and aarch64, because in C mode `mk` never takes this arm at all. Filed rather than fixed because a codegen change no program can exercise is a change made on belief."
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
