---
track: A
prio: 45
type: bug
blocked-by: []
summary: "Redirecting the ucontext PC to a raise stub turns a hardware fault into a catchable Pascal exception — except for a STACK OVERFLOW, where the resumed stub inherits the exhausted SP and re-faults at the identical address forever. A hang, not a crash. The fault-to-raise design needs an SP reset alongside the PC rewrite for this one signal."
status: done
owner: claude-A
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

---

## Resolution (2026-08-21)

`__pxxSigSPPtr` — the sibling the ticket asked for. The address of the saved
**stack pointer** inside the ucontext, alongside `__pxxSigPCPtr`'s saved PC, so a
handler writes both:

```pascal
PPtrUInt(__pxxSigSPPtr)^ := (PtrUInt(@spare[High(spare)]) - 256) and not PtrUInt(15);
PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);
```

Same shape as the PC intrinsic and for the same reason: a POINTER, not a
read/write pair, so both directions are ordinary Pascal and the compiler owns
exactly one new fact — the per-arch offset. `AN_SIGINFO` grows `ASTIVal = 5`,
which lowers to the existing ucontext slot load plus a pointer add, so **no
backend gets a new op** and all six carry it unchanged.

### The offset table was measured, not read off a header

`UContextSPOffset` in `ir.inc`, next to `UContextPCOffset` and by the same rule
that two independent sources must agree. A probe faulted from a frame carrying a
4096-byte pad and dumped every ucontext word within 16K of that pad: the stack
pointer sits a few bytes from it, the FRAME pointer a whole pad away, so the two
are told apart by their delta instead of assumed.

```
x86-64   160 = uc_mcontext(40) + gregs[REG_RSP=15]*8
aarch64  432 = uc_mcontext(176) + fault_address(8) + regs[31]*8
arm32     84 = uc_mcontext(20)  + arm_sp(64)
i386      48 = uc_mcontext(20)  + gregs[REG_ESP=7]*4
riscv32  168 = uc_mcontext(160) + sc_regs.sp, its third field
```

**i386 is the one the dump could not settle**, and it is the reason this was
worth measuring rather than deriving: `gregs[REG_ESP=7]` and
`gregs[REG_UESP=17]` (offsets 48 and 88) hold the *same value* at fault time, so
scanning cannot tell you which one `sigreturn` restores. A differential can —
writing 48 lands the resumed proc on the spare stack, writing 88 leaves it on the
old one. That also matches the kernel struct, which names index 17
`sp_at_signal` and ignores it in `restore_sigcontext`.

### The shadow-chain question the ticket flagged

It answers cleanly, and by measurement: `ExcLongJmp` restores SP from the setjmp
buffer of the frame that owns the `except`, **not** from the resumed context. So
the shadow chain (`BSS_EXC_TOP`) unwinds to a frame on the ORIGINAL stack and the
borrowed one is simply abandoned — the raise stub only ever needs room to reach
`ExcRaise`. `test_stack_overflow_raise` runs 1000 iterations of ordinary work
after the catch to show the original stack is intact.

The compiler deliberately supplies **no** spare stack of its own: how much room a
recovery path needs, and whether it is per-thread, is a program's call. (An
altstack is not a substitute — `SA_ONSTACK` gives the HANDLER a stack, and the
handler was never the problem; it is what the kernel resumes on after sigreturn
that re-faults.)

### Measured

Before, the repro looped exactly as reported — faults 2..4 at an *identical* PC
and address, the raise stub's own prologue on the guard page. After:

```
recursing
caught a stack overflow, hits=1
and execution continued, after=1000
```

`hits=1` is the assertion that matters: it is the difference between a redirect
that took and the fault loop.

### Tests

- `test/test_signal_sp_rewrite.pas` — **all five hosted targets**. Faults with a
  nil write rather than an overflow on purpose, so the handler has a stack
  everywhere; the raise stub reports its own frame address, which can only be
  inside a BSS array because the kernel resumed it on the SP we wrote. This is
  what makes a wrong entry in the five-row offset table fail loudly instead of
  quietly clobbering an unrelated register. Makefile rows added next to each
  existing `test_signal_pc_rewrite` row (native + i386 + arm32 + aarch64 +
  riscv32); all five pass.
- `test/test_stack_overflow_raise.pas` — the end-to-end case, **x86-64 only**,
  and not because the SP rewrite is missing elsewhere: the other four hosted
  targets install their handlers without `SA_ONSTACK`, so for a stack overflow
  the handler never runs at all and there is nobody to do the rewrite. Measured
  on all five and filed as
  [[bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack]]
  (Track A, prio 40) — a pre-existing gap this ticket only made visible.

### Parked, per the ticket's own last question

Whether `EStackOverflow` should be raised **automatically** rather than left to a
hand-written hook is policy, not a bug, so it is a Track U item:
[[decide-should-a-stack-overflow-raise-estackoverflow-by-itself]] — hook vs
default vs a `--fpc-stack-errors` flag mirroring `--fpc-mem-errors`, with the
flag recommended and flagged as needing to be answered together with
[[decide-int-div-zero-behavior-unification]].

### Gate

`make compiler/pascal26` (byte-identical self-host fixedpoint) + the repro +
`tools/gate.sh quick`. Cross-target breadth is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit 9c93264d3.
