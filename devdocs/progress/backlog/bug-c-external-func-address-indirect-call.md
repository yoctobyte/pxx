
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
