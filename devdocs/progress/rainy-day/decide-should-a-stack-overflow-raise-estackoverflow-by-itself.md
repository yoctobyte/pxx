---
slug: decide-should-a-stack-overflow-raise-estackoverflow-by-itself
track: U
status: rainy-day
prio: 15
---

# Decide: should a stack overflow raise EStackOverflow by itself, or stay a hand-written hook?

`__pxxSigSPPtr` + `__pxxSigPCPtr` now make a stack overflow catchable, but only
for a program that writes the hook itself:

```pascal
procedure OnSegv;
begin
  PPtrUInt(__pxxSigSPPtr)^ := (PtrUInt(@spare[High(spare)]) - 256) and not PtrUInt(15);
  PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);
end;
```

FPC raises `EStackOverflow` (runtime error 202) with no user code at all. The
fork is whether pxx should too, and it is a design call, not a bug.

## The fork

**(a) Leave it a hook** — the compiler supplies the two intrinsics and nothing
else. Costs nothing at startup, invents no policy, and keeps the "no silent
behaviour we did not ask for" line. But it means the default experience of a
runaway recursion stays a bare SIGSEGV, and every program that wants FPC's
behaviour re-implements the same eight lines (including getting the alignment
and the headroom right).

**(b) Install it by default** — the signal runtime registers its own SIGSEGV
hook that distinguishes a stack overflow from an ordinary wild pointer (the
fault address is within a page or so of the faulting SP, which the ucontext now
gives us) and raises. Then `try ... except on E: EStackOverflow` just works.
Questions this drags in: where the spare stack comes from (a second BSS block?
the existing `BSS_SIG_ALTSTK`, which the handler is already using?), how much,
and whether it is per-thread — a cloned thread's overflow is the interesting
case and the one a fixed BSS block gets wrong.

**(c) Behind a flag** — `--fpc-stack-errors`, exactly the shape
`--fpc-mem-errors` already has for turning a SIGSEGV into runtime error 216.
This is the precedent-following answer: same family of behaviour, same opt-in,
same reason (FPC parity that costs something is a flag, not a default).

## Recommendation

**(c)**, and reuse `--fpc-mem-errors`' machinery rather than adding a second
flag — a stack overflow is a memory fault, the stub already decodes SIGSEGV, and
runtime error 202 vs 216 is one comparison of the fault address against the
saved SP (both of which the stub has in hand once `UContextSPOffset` exists). The
"raise a catchable Pascal exception" half is a bigger question that overlaps
`decide-int-div-zero-behavior-unification` — where a builtin exception CLASS
should live — and should be answered together with it, not separately.

Blocked on nothing; the intrinsics that would implement any of the three landed
with `bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset`.

## DEFERRED (user, 2026-08-21) — parked to rainy-day, with the direction recorded

> *"much work for little wins, we have other things on our mind"*

Not rejected, and not undecided-in-the-dark: the direction is recorded below so
whoever picks this up does not restart the analysis.

### The user's leaning, if it is ever done

**(b) install it by default, with (c)'s FPC numbering under strict-fpc mode.**
I.e. our own sane behaviour out of the box, and FPC's exact runtime-error
convention behind the mimic flag — not a second user-facing flag of its own.

### Why it is deferred, in the user's own terms

**"We seek LANGUAGE compliance, not error-handling compliance."** FPC parity on
*how a program dies* is worth much less than parity on what the language means,
and this ticket is entirely the former. That principle is worth more than this
ticket: it applies to the whole `--fpc-*-errors` family and it is the reason
none of them should default to FPC's convention.

And the mechanical objection, which is the good one:

> *"having a stack overflow exception handler would ironically use the stack"*

That is the crux and it does not go away. The raise has to land on the MAIN
stack past the guard page, so it needs headroom the faulting program has by
definition run out of. Today's hook makes the program supply its own `spare`
array precisely for this. A fixed BSS block gets the per-thread case wrong, and
a cloned thread's overflow is the interesting one.

## What this ticket got wrong, corrected before parking

Its recommendation deferred the catchable half because *"where a builtin
exception CLASS should live … should be answered together with
`decide-int-div-zero-behavior-unification`."* **That is stale.** The question has
a working answer and four shipped instances: a `PXX*Hook` slot in
`builtinheap.pas`, defaulting to nil = message + `Halt(n)`, which sysutils'
`initialization` upgrades to a catchable raise —

    PXXDivZeroHook -> EDivByZero      PXXOverflowHook   -> EIntOverflow
    PXXRangeErrorHook -> ERangeError  PXXIoErrorHook    -> EInOutError

with a fifth (`PXXNilRefHook` -> `EAccessViolation`) specified in
[[feature-a-emitted-nil-checks]]. So the exception-class home needs no design
round — it needs `PXXStackOverflowHook` and an `EStackOverflow`, which does
**not** exist in sysutils today.

The design was never the blocker. The headroom is.

## The cheap half, separable and NOT parked with the rest

Reporting **202 instead of 216** for a stack overflow is one comparison of
`si_addr` against the saved SP — both already in hand inside the
`--fpc-mem-errors` stub, which already decodes SIGSEGV. It needs no headroom, no
new flag and no exception class, and the parent bug
([[bug-a-a-memory-fault-is-a-raw-sigsegv-not-runtime-error-216]]) already lists
it as a known gap. If anyone touches that stub for another reason, fold it in;
it does not justify a session of its own.

Also settled while parking: **do not add `--fpc-stack-errors`.** A stack overflow
is a memory fault, the stub already decodes SIGSEGV, and one flag reporting FPC's
numbers explains better than two split by fault kind.
