---
prio: 55  # auto
---

# C: taking &fprintf (crtl variadic) and calling through the pointer SIGSEGVs

- **Type:** bug. Track C (crtl binding / variadic-through-pointer).
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00189: `int (*fprintfptr)(FILE *, const char *, ...) = &fprintf;` then
  `fprintfptr(stdout, "%d\n", ...)` — exit 139. fprintf never called directly,
  so the crtl auto-pull may not fire for address-of-only use, OR indirect call
  of a variadic loses the variadic call-site protocol. Note `(*f)(24)` through
  a plain fnptr works elsewhere → suspect variadic-indirect or &external-crtl.

## Repro ladder
1. `&puts` via pointer (non-variadic crtl) — isolate auto-pull-on-address-of.
2. own variadic fn via pointer — isolate variadic-indirect call protocol.

## Gate
Drop 00189.c from test/c-conformance/pxx.skip; runner green.
