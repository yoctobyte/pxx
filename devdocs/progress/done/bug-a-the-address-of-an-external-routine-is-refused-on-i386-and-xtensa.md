---
track: A
prio: 55
type: bug
status: done
found: 2026-09-01
found-by: frankC
summary: "i386 FIXED 2026-09-01, xtensa still open and it is a DIFFERENT mechanism. i386 now routes @external through the same GOT slot its external CALL already used -- `mov eax, [abs32]` where the call is `call dword [abs32]` -- added as the missing i386 arm of the shared EmitExternalProcAddr, which already had x86-64, aarch64, arm32 and riscv32. Measured: the minimised repro compiles and, linked against a gcc -m32 host that owns the symbol, calls through and returns 42. XTENSA CANNOT COPY THIS: it has no DynCall/GOT external path at all (no DynCallCodePos anywhere in ir_codegen_xtensa.inc), so its externals resolve by a different model and the fix needs that model understood first. Confirmed still refused there, reduced away from stdio because `#include <stdio.h>` independently fails on xtensa (bug-c-including-stdio-h-refuses-to-compile-for-xtensa, filed). The stated value of this ticket -- unblocking test-c-abi-mixed-link's i386 arm so its other 13 rows report again -- is DELIVERED."
owner: frankA
---

# The address of an external routine is refused on i386 and xtensa

```c
extern int gcc_thing(int);
typedef int (*fn)(int);
int use(void) { fn f = gcc_thing; return f(1); }
```

| target | result |
| --- | --- |
| x86-64 | compiles |
| i386 | `error: @ on external routine not supported; wrap it in a local routine` |
| xtensa | same message, `ir_codegen_xtensa.inc:4177` |

The suggested workaround in the message ("wrap it in a local routine") is not
available to a C program that receives the pointer from a table it does not
own, and it is not something a compiler can ask of hand-written C.

## Why it surfaced now, and the one thing to know before fixing

`test-c-abi-mixed-link` gained two rows that pass a struct through a function
POINTER, to close a hole in that gate (the indirect cdecl arm classified
arguments in its own loop and had not been converted). Those rows initialise a
fn-pointer from an `extern`, so the i386 arm of the gate now fails at COMPILE
time rather than at run time.

**That is a loss of information, not a new defect.** i386 was already red there
and stays red; but a compile failure means the other 13 rows report nothing, so
whoever implements i386's aggregate ABI cannot see which of them their work has
fixed. **Fixing this unblocks the diagnosis, not the feature** — worth doing
first for that reason rather than for its own weight.

x86-64 reaches the address through the GOT for an external
(`EmitExternalProcAddr` and the `PatchDynCallSites` relocation path). i386 has
the same dynamic machinery for CALLS; it is the address-of arm that was never
written.

## Related

- [[bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee]]
  — the gate this surfaced under; its i386 half is still open.
- `test/cexternal_proc_addr_callable.c` asserts an external's address is
  CALLABLE and not merely non-nil; it is x86-64/aarch64 only for this reason.

---

## i386 done 2026-09-01 (frankA); xtensa open

    minimised repro, i386     refused  ->  compiles
    linked, gcc -m32 host                  returns 42 (calls through correctly)

The fix is one arm in `EmitExternalProcAddr` (symtab.inc), which already carried
x86-64, aarch64, arm32 and riscv32 — i386 and xtensa were simply absent, and the
per-backend refusal was standing in for the missing arm.

**Why the encoding needed care rather than copying.** ModRM `$05` is
`mod=00 rm=101`, which is an absolute disp32 on i386 and rip-relative on x86-64
— the same two bytes meaning different things per target. It needed no new patch
arm because `PatchDynCallSites` already splits exactly on that: x86-64 gets a
distance, everything else gets the absolute slot VA. A refusal is loud and a
wrong address is silent, so the test ROWS the call rather than only compiling it.

## Xtensa: measured, and not the same fix

Still refused (`ir_codegen_xtensa.inc:4177`), confirmed on a repro reduced away
from `stdio.h` — because `#include <stdio.h>` fails on xtensa for an unrelated
reason, filed as `bug-c-including-stdio-h-refuses-to-compile-for-xtensa`. Worth
knowing before anyone tries to reproduce this one there: the obvious repro dies
before it reaches the site.

**`grep DynCallCodePos ir_codegen_xtensa.inc` returns nothing.** Xtensa has no
GOT-slot external-call path to hang this on, so the i386 answer does not
transfer — its externals resolve through some other model, and that model has to
be read before an arm can be written. That is the whole of the remaining work,
and it is why this is parked rather than finished.

## xtensa: resolved

frankA, 2026-09-01. Compiler `102942dd50cf`. Regression rows: `test-emit-obj`
block 4b-nonies, riscv32 and xtensa.

**The recorded reason it could not be done was about the wrong half of the
mechanism.** This ticket said xtensa "has no DynCall/GOT external path at all
(no DynCallCodePos anywhere in ir_codegen_xtensa.inc)". It has no GOT — true —
but it does have DynCall, and an ordinary `extern` CALL already emits exactly
one `R_XTENSA_32` against the UND symbol. Measured before touching anything:
`extern int gcc_thing(int); int use1(void){ return gcc_thing(1); }` produces
`0000002c R_XTENSA_32 gcc_thing + 0`. The address lives in a literal, which is
what the target does for a call — so taking the address is the call path minus
the call, and the missing arm is the riscv32 one with xtensa's literal shape.

The grep was accurate and the conclusion drawn from it was not: `DynCallCodePos`
is written in `symtab.inc`'s shared emitters, never in a per-target codegen
file, so its absence from `ir_codegen_xtensa.inc` says nothing about whether
xtensa has the path.

**The fix** is a `TARGET_XTENSA` arm in `EmitExternalProcAddr` beside the
riscv32 one, and `IR_PROCADDR` in `ir_codegen_xtensa.inc` routing an external
there instead of erroring — the local-`@proc` path below it keeps its
`ProcAddrFix` literal, which patches to `entry+BodyAddr` and has no meaning for
an external.

**Verified structurally, NOT by execution, and the limit is real.** An xtensa
EXECUTABLE refuses external dynamic symbols outright ("this backend emits no
dynamic segment"), and the C frontend has no xtensa entry stub, so there is no
way to run an `@external` on xtensa from this box. What can be checked is the
object, and it now matches riscv32's already-accepted arm row for row: a bare
call names the external in 1 relocation, taking its address names it in 3, on
BOTH targets. The regression row asserts the DIFFERENCE and asserts the
call-only control is nonzero first — a row asserting only that the fixture
compiles would pass on a backend emitting no reference at all.

Both targets in the title are now done, so this leaves `unfinished/`.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b13212f43.
