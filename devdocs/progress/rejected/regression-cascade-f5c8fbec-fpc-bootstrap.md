---
prio: 0
---

# Cascade sweep: 939 auto-filed regressions at f5c8fbec6016 — one root cause, already fixed

- **Type:** triage note (fable-O, 2026-07-18 evening) covering the 939
  `regression-*` tickets auto-filed by twatch(borg) at bad `f5c8fbec6016`,
  bulk-moved here.
- **Root cause:** ONE missing FPC-seed forward — the aarch64 residency mirror
  (588d525c) called `RegcallScalarType` from `ir_codegen_aarch64.inc`, included
  before the defining `ir_codegen.inc`. PXX's prescan resolves it (all native
  gates green); the single-pass FPC seed does not → `fpc-bootstrap` red → every
  FPC-dependent job (lib-fpc-clean, the test-asm suite, the FPC-built test-core
  sweep) cascaded red on the next watcher pass, and each red auto-filed a ticket.
- **Fix:** `938c0154`-adjacent `forwards.inc` forward (commit "fix(A):
  forward-declare RegcallScalarType for the FPC seed path"). Borg's follow-up
  report (`2185b272`) confirms **FIXED**: fpc-bootstrap, lib-fpc-clean,
  test-asm.
- Not individually triaged — they share the one bad SHA and the one root cause.
  If any of these jobs shows red at a LATER sha, that is a NEW finding: file
  fresh, do not resurrect these.
- Watcher-behavior observation for Track T: a red `fpc-bootstrap` should
  probably SUPPRESS (or fold into one ticket) the downstream FPC-dependent
  jobs' auto-filing — 939 tickets for one missing forward is noise that buries
  real signal. Left as a suggestion, not filed as a T ticket.
