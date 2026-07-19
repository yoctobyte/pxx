---
track: A
prio: 55
type: feature
---

# A real declaration phase: all decls before any body is typed

Design: `devdocs/dev/type-identity-as-substrate.md` item 3.

Today (NilPy, the measured case): `PyRegisterClassShells` registers class NAMES,
then module locals are inferred, then `PyRegisterClassMembers` registers MEMBERS
last. So at inference time every class has zero fields — measured directly:
`ciOuter=1, fcOuter=0`. That ordering is why a field pre-pass had to be bolted
on (`PyRegisterClassFieldsPrepass`), and it is a patch, not the fix.

Collect ALL declarations — shells, members, signatures — before typing any body.
Check whether the other frontends have the same latent ordering hazard or only
NilPy does.

Pairs with [[feature-n-nilpy-ast-based-typing]]; doing that one first may
subsume part of this.
