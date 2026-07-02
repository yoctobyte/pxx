# Remove the sysutils Move/FillChar copies (now shadowed by builtin)

- **Type:** task (library cleanup) — **Track B** (lib/** ownership)
- **Status:** backlog
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
