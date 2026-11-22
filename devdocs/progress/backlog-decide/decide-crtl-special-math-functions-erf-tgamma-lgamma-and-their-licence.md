---
slug: decide-crtl-special-math-functions-erf-tgamma-lgamma-and-their-licence
track: crtl
prio: 30
type: decide
status: backlog
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [crtl, math, licence, owner]
blocked-by: []
summary: "crtl's math has no erf, erfc, tgamma or lgamma (C99). micropython's math module uses all four when MICROPY_PY_MATH_SPECIAL_FUNCTIONS is on, which is the unix port's default. The usual implementations are fdlibm/musl derived (Sun's permissive notice, MIT for musl); crtl is zlib-licensed. Owner to decide: take musl's code with its notice, or write our own to glibc's accuracy."
---

# Special math functions in crtl, and the licence they come under

## The gap

C99 `<math.h>`: `erf`, `erfc`, `tgamma`, `lgamma` (plus the `f`/`l` forms).
crtl has none of them. micropython's `math.erf`, `math.erfc`, `math.gamma` and
`math.lgamma` call them. The scratch build turned them off
(`-DMICROPY_PY_MATH_SPECIAL_FUNCTIONS=0`). The four math tests that use them
failed with gcc too (glibc's accuracy against micropython's expected text), so
the comparison is unaffected.

## The question for the owner

Accurate versions are not short. The standard sources are:

- **fdlibm / FreeBSD msun** (s_erf.c, e_lgamma_r.c): Sun's notice, "Permission
  to use, copy, modify, and distribute this software is freely granted,
  provided that this notice is preserved." Permissive, but a notice to carry.
- **musl** (src/math/erf.c, lgamma_r.c, tgamma.c): MIT, derived from the same
  fdlibm code, so both notices apply.
- **Our own**, for example erf by rational approximation and tgamma by Lanczos.
  Simpler, but it would be measured against glibc to a few ulp, not fewer.

crtl's files are `SPDX-License-Identifier: Zlib`. Taking third-party code means a
file with a different SPDX line and its notice kept intact. I did not copy any
of it.

Options:
1. musl's four files under MIT, with the fdlibm notice;
2. write our own and test against glibc on a sweep of inputs;
3. leave it, and document `MICROPY_PY_MATH_SPECIAL_FUNCTIONS=0`.
