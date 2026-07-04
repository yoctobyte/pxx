# Remove the sysutils Move/FillChar copies (now shadowed by builtin)

- **Type:** task (library cleanup) — **Track B** (lib/** ownership)
- **Status:** DONE 2026-07-04 — removed both decls (interface) + both bodies
  (impl) from lib/rtl/sysutils.pas; builtin Move/FillChar (in pin v171, well
  past v145) resolves every call. `make lib-test` green (sysutils test incl.)
  + 19 demos OK against pinned v171. No behavior change (byte-identical impl).
- **Opened:** 2026-07-02 by Track A while landing the builtin-home half of
  [[feature-move-fillchar-intrinsics]] (v145).

`Move`/`FillChar` moved to `compiler/builtin/builtin.pas` (auto-pulled, no
`uses` needed, FPC System parity). The identical copies in
`lib/rtl/sysutils.pas` (interface ~line 95, impl ~line 347) are now dead
weight: builtin registers first, so FindProc resolves every call to the
builtin versions. Track A did not touch lib/** per file-ownership rules.

Remove the two decls + two bodies from sysutils; `make lib-test` + demos
green against a pin that includes v145 (the builtin versions must be in the
stable binary BEFORE the copies disappear, else sysutils users lose the
symbol). No behavior change expected — the implementations are byte-for-byte
the same Pascal.
