---
track: A
prio: 45
type: bug
blocked-by: []
summary: "Redirecting the ucontext PC to a raise stub turns a hardware fault into a catchable Pascal exception — except for a STACK OVERFLOW, where the resumed stub inherits the exhausted SP and re-faults at the identical address forever. A hang, not a crash. The fault-to-raise design needs an SP reset alongside the PC rewrite for this one signal."
status: backlog
owner: ""
---

# Stack-overflow fault-to-raise loops forever without an SP reset

- **Track A** (runtime / signal machinery — `ir_codegen.inc`'s signal stubs, and
  whatever library layer eventually owns fault-to-raise).
- Found 2026-08-20 immediately after
  [[feature-signal-siginfo-ucontext]] item 3 landed sigaltstack, which is what
  made the case reachable at all.

## What happens

`__pxxSigPCPtr` lets a handler point the interrupted PC at a raise stub, and
returning from the handler resumes there instead of re-running the faulting
instruction. That is the documented fault-to-raise path and
`test/test_signal_pc_rewrite.pas` proves it end to end for a jump-to-$DEAD0000
fault.

Do the same for a **stack overflow** and the program hangs:

```pascal
procedure OnSegv;
begin
  Inc(hits);
  PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);   { Raiser does `raise 99` }
end;
...
try Recurse; except WriteLn('caught') end;
```

Measured, with a counter added to break the loop:

```
fault 1 addr=140726534331400
fault 2 addr=140726534331400
fault 3 addr=140726534331400
re-faulted 4 times; addr=140726534331400
```

**The same address every time.** Without the counter: `exit=124` under a 30s
timeout — an infinite fault loop.

## Root cause

The PC rewrite is the only thing rewritten. The kernel resumes the redirect
target with the **faulting frame's SP**, which for a stack overflow is by
definition a stack with nothing left — so the raise stub's own prologue touches
the guard page and faults again, at the identical address, forever. The handler
itself keeps running fine, because sigaltstack gave it separate ground; it is
the *resumed* code that has nowhere to stand.

Note this is the one signal where the existing design's assumption breaks. For
every other fault the faulting SP is perfectly usable, which is why
`test_signal_pc_rewrite` passes and why the gap was invisible until a stack
overflow could reach a handler at all.

## Not a regression

Before sigaltstack landed, this program died with exit 139 and the hook never
ran. Nothing that worked before behaves differently now: the ordinary
hook-and-return case exits cleanly (`test/test_signal_altstack.pas`). This is a
sharp edge on a **newly reachable** capability, not a behaviour change.

## What a fix needs

Reset SP in the ucontext alongside the PC — unwind it to a frame that has room,
or point it at a small dedicated raise stack. Both are per-arch (the SP slot
sits at a different ucontext offset on each target, the same per-arch offset
problem `__pxxSigPCPtr` already solved and should be mirrored for), so the
natural shape is a `__pxxSigSPPtr` sibling.

The harder half is not mechanical: after resetting SP, the exception runtime
unwinds through its **own** shadow stack (`BSS_EXC_TOP`, a chain of setjmp
buffers), not the hardware stack — which is exactly why a raise is legal from a
kernel-resumed context at all. Whether a handler-chosen SP stays consistent with
that shadow chain is the question to answer before building, and it wants
measuring rather than reasoning about.

Worth deciding at the same time whether `EStackOverflow` should be raised
automatically rather than left to a hand-written hook — that is a library/policy
question of the same family as
[[decide-int-div-zero-behavior-unification]], and probably a Track U item.

## Gate

A stack overflow caught by a `try ... except` and execution continuing, with the
existing signal suite green (`test_signal_handlers`, `test_signal_siginfo`,
`test_signal_pc_rewrite`, `test_signal_altstack`) + self-host byte-identical.
