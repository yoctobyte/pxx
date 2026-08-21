---
slug: decide-should-a-stack-overflow-raise-estackoverflow-by-itself
track: U
prio: 35
status: backlog
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
