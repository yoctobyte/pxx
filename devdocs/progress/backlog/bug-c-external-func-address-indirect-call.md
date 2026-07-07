
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
