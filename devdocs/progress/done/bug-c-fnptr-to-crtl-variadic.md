---
blocked-by: [bug-c-external-func-address-indirect-call]
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

## Update 2026-07-07
The `&func` (internal) global-fnptr init bug was fixed (b161). The remaining 00189 failure = calling an EXTERNAL crtl function (fprintf/puts) through a pointer prints nothing — now tracked as [[bug-c-external-func-address-indirect-call]]. Blocked on that.


## RESOLVED 2026-07-07 (Track A+C, sole-A)
Two fixes landed. (1) The blocker [[bug-c-external-func-address-indirect-call]]
— string args through a fnptr weren't char*-decayed. (2) This ticket proper: the
cdecl INDIRECT-call path (IR_CALL_IND, ir_codegen.inc) sized the call by
`ParamCount + IRC`, dropping every variadic (`...`) arg, and classified args by
`Procs[cpi].Params[i-IRC]` which reads OUT OF BOUNDS past the declared params.
Fixes: use the walked arg count as nArgs; classify variadic args (beyond
ParamCount) by their own IR type, not Params[]; guard the tySingle narrowing the
same way (variadic floats are promoted to double, never narrowed).
00189 now exits 0 with "yo 24 / 42" (the inner `(*f)(24)` fires and fprintf gets
its variadic 42). Dropped from pxx.skip → conformance 195/0. Regression b170
(own variadic fn through a pointer, crtl-free). make test self-host byte-identical
+ lua green.
