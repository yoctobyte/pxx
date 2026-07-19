---
track: B
prio: 10
type: feature
---

# RTL math.pas on the crtl dd kernels — correct rounding for Pascal too

- **Track:** B (lib/rtl/math.pas + lib/crtl/src/math.c). Tag: compat.
  Rainy-day (user 2026-07-19: "not bothered for now").

crtl's libm is correctly rounded across the whole surface (b377-b385 dd
kernels); Pascal's Exp/Ln/Sin/... are the old ~1-ulp series. Route the
Pascal routines onto the C kernels (Pascal wraps C — the REVERSE of the old
direction), so Pascal inherits correct rounding free and there is one libm.

Notes for the implementer:
- Pascal `Exp` calling `__crtl_exp` is binding-safe (no case-insensitive
  collision — that hazard is only same-name, see the b377 landmine).
- Self-host implications: if the compiler binary itself uses Exp/Ln (float
  printing, constant folding), its output bits change -> reseed / codegen-
  differ expected on the transition commit ([[codegen-reseed]] memory).
- Single/overload surface of math.pas must keep its FPC-compat signatures.
- The dd kernels live in C sources; a Pascal program today only links crtl
  when C objects are present — needs a pull path (builtin unit or crtl-as-
  unit) before Pascal can call them. That plumbing is the actual work.
