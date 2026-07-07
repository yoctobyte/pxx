
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
