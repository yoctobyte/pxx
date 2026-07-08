---
prio: 45
---

# C/i386: call through a pointer to a VARIADIC function (fnptr = &fprintf) segfaults (00189)

- **Type:** bug (i386 variadic indirect-call marshalling). Track A.
- **Found:** 2026-07-08 by the C cross-conformance matrix
  (feature-c-cross-target-feature-coverage). i386 ONLY (exit 139 = SIGSEGV);
  x86-64, aarch64, arm32, riscv32 pass.

## Repro (c-testsuite 00189)
```c
int (*fprintfptr)(FILE *, const char *, ...) = &fprintf;
fprintfptr(stdout, "%d\n", (*f)(24));   /* i386: SIGSEGV */
```
fprintf is never called directly (that's the point of the test), so the
callee is only reachable through the pointer — the i386 indirect-call path
must marshal the variadic frame the same way the direct variadic call does
(the v178 i386 variadic ABI work covered direct calls).

## Gate
00189 passes under `tools/run_c_conformance.sh --target i386`; drop its line
from `test/c-conformance/pxx.skip.i386`.
