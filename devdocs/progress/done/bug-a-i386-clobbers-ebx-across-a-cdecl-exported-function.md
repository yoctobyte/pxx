---
track: A
prio: 65
type: bug
status: done
found: 2026-08-31
found-by: frankC
owner: frankA
blocked-by: []
summary: "On i386 a pxx routine clobbers EBX, ESI and EDI -- all three callee-saved in the i386 psABI -- and restores none of them, so a C caller that keeps a live value there gets a wrong value or a SIGSEGV on return. CORRECTED 2026-08-31 while fixing: the original 'ESI and EDI ARE preserved, it is EBX alone (mask 0x1)' was an artifact of the probe's one-line body, which never reached an esi/edi path; a body doing int64/div/mod/shift/array/string work measures mask 0x7. x86-64 is CLEAN -- rbx and r12-r15 all preserved, same probe. Unobservable before 2026-08-31 because nothing outside pxx could call in on i386; the i386 object writer made it reachable and it showed up within minutes as a SIGSEGV in a printf-using gcc -m32 caller whose pxx function had ALREADY RETURNED THE RIGHT ANSWER. NOT the C-ABI decide's fork: it bites Pascal `cdecl`, where CProcUsesCAbi is already True. FIXED: the i386 prologue spills all three to frame slots and every epilogue reloads them."
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


## Fix (frankA, 2026-08-31)

`compiler/symtab.inc`, entirely inside the i386 arms — x86-64 and the four cross
targets are untouched:

- `EmitProcPrologue` reserves 12 frame bytes (`FrameSize + 12`) and spills
  ebx/esi/edi to them right after `sub esp,imm32`.
- `EmitProcEpilog` reloads all three immediately before `leave; ret`. That one
  site covers **every** return path — an early `Exit` is emitted by
  `ir_codegen386.inc:4831` calling `EmitProcEpilog`, not by an open-coded `ret`
  (checked: `symtab.inc:11758` is the only i386 `leave; ret`).
- `PatchProcPrologue` releases the entry.

**Unconditional, not liveness-tracked** — a deliberate deviation from this
ticket's own suggestion. `ir_codegen386.inc` has 44 ebx / 35 esi / 42 edi write
sites (ebx is also the `int 0x80` arg0 register); a "did this body write it?"
flag would have to be maintained at every one of them, and a single missed site
reproduces this exact bug invisibly. Three stores and three loads per frame is
the cheaper trade.

**The offsets are a LIFO, not a global scalar.** i386 prologue emission *nests*:
measured at depth 2 on `test/test_zig_advanced.zig` (0 on `compiler.pas`, on
triple-nested Pascal procedures, on a nested NilPy `def`, and on C — Pascal and
NilPy emit an inner routine's body to completion *before* the outer prologue, so
the obvious single global tests clean on four frontends and is silently wrong on
the fifth). A single global would have made an outer routine's epilogue reload an
inner routine's slots. `I386_CS_SAVE_MAX = 64` with a hard `Error` on overflow.

### Measured, compiler sha256 `fb68a748bcee3da3`

| body | before | after |
| --- | --- | --- |
| `a*10+b` (this ticket's repro) | mask `0x1` | **`0x0`** |
| int64/div/mod/shift/array/string | mask `0x7` | **`0x0`** |
| x86-64 control, same source | `0x0` | `0x0` |

The `printf`-using `gcc -m32 -no-pie` caller that motivated the ticket now exits
0 and prints the right value. Values are also differentially correct, not merely
non-crashing: i386 and x86-64 return identical results for the rich body over
four inputs (`44096 38541 51780 59995`).

**Residual owner:** the mask probe only covers what a *cdecl-exported* routine
does. Nothing here checks the direction pxx→C on i386 (whether pxx assumes its
own callee-saved registers survive a call *out* to a C function); that is a
separate question and this ticket does not answer it.

### Regression row (`make test-emit-obj`)

`test/test_emit_obj_386_callee_saved.pas` + `tools/i386_callee_saved_caller.c`,
wired as row 4c. Two halves:

- **Structural**, no multilib needed, so it guards on every box: the three
  spills must sit in the three instructions after `sub esp`, the three reloads
  in the three before `leave`. Exact windows, not a body-wide search a stray
  `mov ebx,...` would satisfy.
- **Runtime**: the C oracle returns the clobber mask as its *exit status* and
  never printfs on the checking path — glibc keeps the GOT pointer in ebx, so a
  probe that prints its own result cannot separate a clobbered register from a
  dead reporting channel. It asserts the return value too, so "preserved the
  registers by breaking the function" fails instead of passing quietly.

**Positive control, run rather than assumed:** with the fix stashed and the
compiler rebuilt (pre-fix sha256 `7ea31a827aae`), the runtime half returns mask
`7` and all six structural assertions fail. With the fix (`fb68a748bcee`) the
mask is `0` and all six pass.

Note that row 4b — a `printf`-using `gcc -m32` caller against a pxx i386 object
— existed already and never caught this, because its exported function is
`a*10+b`. That is the same simple-body blind spot that produced the summary's
original "ESI and EDI ARE preserved". Keep 4c's body rich.

### Also verified

- **i386 native self-host fixedpoint still holds**, which is the real breadth
  test here since every i386 frame changed: gen1 (x86-64-cross-built) == gen2 ==
  gen3, all `b4f727d83f01f659`, and the resulting compiler builds and runs a
  string/div program correctly.
- `tools/gate.sh quick` GREEN. x86-64 untouched — same source, same probe, mask
  `0x0` before and after, and every edit is inside an `if TargetArch =
  TARGET_I386` arm.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
