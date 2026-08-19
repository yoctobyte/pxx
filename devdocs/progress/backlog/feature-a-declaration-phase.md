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

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted — internal, no user-visible symptom.** The
bolted-on `PyRegisterClassFieldsPrepass` this ticket calls "a patch, not the
fix" is still in `compiler/pyparser.inc` and still load-bearing (three sites
reference it, one of them documenting the dependency explicitly), so nothing
here landed incidentally. Not a mis-typed bug: it describes an ordering
hazard inside the compiler, not a program that misbehaves.
