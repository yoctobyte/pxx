---
track: A
prio: 65
type: bug
status: backlog
found: 2026-08-31
found-by: frankC
owner: ""
blocked-by: []
summary: "On i386 a pxx routine clobbers EBX -- callee-saved in the i386 psABI -- and does not restore it, so a C caller that keeps a live value there gets a wrong value or a SIGSEGV on return. ESI and EDI ARE preserved; it is EBX alone (measured with an asm probe: clobber mask 0x1 of ebx=1/esi=2/edi=4). x86-64 is CLEAN -- rbx and r12-r15 all preserved, same probe. Unobservable before 2026-08-31 because nothing outside pxx could call in on i386; the i386 object writer made it reachable and it showed up within minutes as a SIGSEGV in a printf-using gcc -m32 caller whose pxx function had ALREADY RETURNED THE RIGHT ANSWER. NOT the C-ABI decide's fork: it bites Pascal `cdecl`, where CProcUsesCAbi is already True."
---

# i386 clobbers EBX across a cdecl-exported function

The i386 prologue is `push ebp; mov ebp,esp; sub esp,imm32` and the epilogue is
`leave; ret`. Nothing saves **EBX**, and the integer codegen uses it — e.g. as a
scratch in the 64-bit multiply expansion. EBX is callee-saved in the i386 psABI.

## Repro, and note what it looks like from outside

```pascal
program abipas;
function p_ii(a, b: Integer): Integer; cdecl;
begin p_ii := a*10 + b; end;
begin
end.
```

```
pascal26 --target=i386 --emit-obj abi.pas abipas386.o
```

```c
#include <stdio.h>
int p_ii(int,int);
int main(void){ printf("%d\n", p_ii(1,2)); return 0; }
```

`gcc -m32 -no-pie` → **SIGSEGV**. But

```c
int main(void){ return p_ii(1,2)==12 ? 0 : 1; }
```

exits 0. **The function computes the right answer and then breaks its caller**,
which is why this reads as a relocation or writer bug and is not one. That was
the first hypothesis here and it cost a detour; the disassembly is clean and
`p_ii` is correct.

## Measured, not inferred

An assembly probe that sets markers in ebx/esi/edi, calls `p_ii(1,2)`, and
returns a bitmask of what changed:

| target | probe result |
| --- | --- |
| i386 | mask `0x1` — **EBX clobbered**, ESI and EDI preserved |
| x86-64 | mask `0x0` — rbx, r12, r13, r14, r15 all preserved |

So it is one register on one target, not a general "we do not save
callee-saved registers" — which matters, because the cheap fix (blanket
push/pop of all three in every prologue) would pay for two registers that are
already right.

Compiler `cc0ef3dc2b44`, probes in the ticket's repro above.

## Why it appears now

Nothing outside pxx could call into pxx-compiled i386 code until
[[feature-a-object-output-for-i386-arm32-and-aarch64]] landed the object writer.
Within pxx everything obeys the same internal convention, so a clobber of EBX
is invisible: **self-consistency again, the same mechanism that hid the C-ABI
divergence on three targets.**

## What it is NOT

**Not the C-ABI fork.** It bites Pascal `cdecl`, where `CProcUsesCAbi` is
already True and the C convention is already selected. Whichever way
[[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]]
is ruled, this stays broken until the prologue saves EBX.

## Suggested shape

Save and restore EBX in the i386 prologue/epilogue **only when the routine's
body actually writes it** — a blanket push/pop costs every call in every i386
program for a register most routines never touch. If that liveness question is
not cheaply answerable where the prologue is emitted, do it unconditionally for
routines the object writer EXPORTS (`ObjProcIsExported`), which is the only
population an external caller can reach, and file the general case behind it.

## Umbrella

[[meta-a-pxx-produces-linkable-code]] — found by the capability it created.
