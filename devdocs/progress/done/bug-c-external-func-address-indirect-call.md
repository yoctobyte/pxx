---
prio: 55
# C: address of an EXTERNAL function called through a pointer does nothing

- **Type:** bug (codegen — external proc address for indirect call). Track A/C.
- **Found:** 2026-07-07, isolating 00189 (bug-c-fnptr-to-crtl-variadic).
- **Blocks:** [[bug-c-fnptr-to-crtl-variadic]] (00189).

## Symptom
Calling an EXTERNAL (crtl) function through a function pointer produces no output
/ wrong behaviour — the indirect call goes to a wrong address. Own (internal)
functions via a pointer work.

```c
#include <stdio.h>
int (*p)(const char*) = puts;      /* or &puts, local or global */
int main(){ p("hi"); return 0; }   /* prints nothing */
```
Both local and global pointers, bare or address-of, are affected — so it is the
proc-ADDRESS of an external symbol that is wrong for an indirect call, not the
pointer-init path (that was the separate &func fix, commit caab6bde). Direct calls
to the same externals work.

## Likely site
Wherever a bare/address-of external function name is lowered to a code-address
value (IR_PROCADDR / the fn-pointer decay). An external proc's address is
probably emitted as 0 / an unrelinked slot rather than its resolved code address.

## Gate
puts/fprintf via a pointer prints; 00189 matches (dropped from pxx.skip).

## Analysis 2026-07-07 (isolated, not yet fixed)
Located to the proc-address path, NOT the pointer-init:
- `IR_PROCADDR` (ir_codegen.inc:1650) routes an external proc to
  `EmitExternalProcAddr` (symtab.inc:5246), which loads the function pointer
  from the **DynCall GOT slot** (`mov rax,[abs GOT slot]`, patched by
  PatchDynCallSites) — the dynamic path.
- In a libc-free STATIC binary the crtl functions (puts/fprintf) are linked
  INTERNALLY; direct CALLs resolve fine, but the address-of via the GOT slot
  yields a wrong/undispatched pointer, so an indirect call through it does
  nothing.
- Repro: `int(*p)(const char*)=puts; p("hi");` prints nothing (local or global,
  bare or `&`). `sizeof`/aSyscall-style address-of "works" only because those
  pointers are never actually called.

Likely fix direction: when an "external" proc actually has an internal
definition/resolution in this link (crtl), IR_PROCADDR should use the internal
code-address fixup (the non-external branch at ir_codegen.inc:1655) rather than
the GOT slot — or PatchDynCallSites must fill the address-of slot with the
resolved internal address. Track A (codegen/linking) — focused session; verify
across targets + that sqlite aSyscall + direct calls still work.

## Refined 2026-07-07 — still broken after crtl-bind; external-vs-internal is the crux
Re-tested after feature-c-crtl-bind: puts/fprintf via a pointer STILL produce no
output (00189 still fails). Key facts:
- An OWN (locally-defined) function via a global pointer works (prints).
- A defined proc sets ProcExternal:=False (cparser.inc:5286) and ProcBodyCompiled.
- #include <stdio.h> auto-pulls the sibling crtl .c (puts's impl), so puts SHOULD
  become internal — yet its address via a pointer is still wrong.
So either the crtl impl for these isn't actually compiled-in as an internal proc
(puts stays ProcExternal -> IR_PROCADDR's GOT/DynCall address path, which is
un-patched for a libc-free static binary), or IR_PROCADDR mis-handles it. Next
step: instrument whether ProcExternal[puts] is true at the IR_PROCADDR site; if
true despite the pull, the fix is to route an external-with-a-compiled-body proc
through the INTERNAL code-address fixup (ir_codegen.inc:1655) not
EmitExternalProcAddr. Deep codegen/linking, focused session.

## Precise pin 2026-07-07 (hypothesis tested + reverted)
Baseline confirmed: DIRECT `puts("x")`/`printf(...)` WORK in the libc-free static
binary (EmitCallProc's DynCall slot is patched to the crtl impl address). Only
taking the ADDRESS fails. puts is ProcExternal AND `ProcBodyCompiled = FALSE`
(it's DynCall-resolved, not compiled as a normal internal proc), so the tried
fix "route IR_PROCADDR through the internal fixup when ProcBodyCompiled" did
NOT apply and was reverted.
Real root cause: a global init `int (*p)(const char*) = puts;` records puts as a
proc-address PendingInit, but an EXTERNAL proc has no compile-time constant
address — its address is a DynCall slot resolved by PatchDynCallSites. The
proc-address PendingInit materializer (and IR_PROCADDR/EmitExternalProcAddr for
the value form) needs to emit a DynCall-slot LOAD / fixup for an external proc,
the same mechanism the direct CALL uses — currently the address paths leave it 0.
Fix: make the external-proc address paths (global-init proc-address PendingInit +
IR_PROCADDR) go through RegisterExternal + a patched DynCall slot like the call
path. Deep linking/codegen, focused session.


## RESOLVED 2026-07-07 (Track A+C, sole-A)
Root cause was NOT the proc address. Verified `int(*p)(const char*)=puts` stores
the CORRECT address (`p==puts==0x41d388`, printf %p) — direct call and address
both fine. The blank output came from the string-literal ARGUMENT: `AN_CALL_IND`
lowering (ir.inc) never applied the char* (+8) length-prefix skip that the direct
`AN_CALL` path applies to a frozen string literal handed to a `char*` param. So
`p("hello")` passed the Pascal length word, and the callee printed nothing. Int
args worked (isolated with `putchar` fnptr → "AB", `puts` fnptr → blank).

Fix (ir.inc, AN_CALL_IND arg loop): mirror the direct-call marshalling — string
literal → tyPointer param (or variadic slot) gets IR_BINOP(+8); managed string →
pointer param passes as-is. C-mode only; Pascal self-build byte-identical.
Gate: make test (self-host byte-identical) + c-conformance 194/0 + lua + sqlite
threads all green.
