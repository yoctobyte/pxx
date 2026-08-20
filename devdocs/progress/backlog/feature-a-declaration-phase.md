---
track: N
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


## Answered 2026-08-20 (Track A): the hazard is NilPy-only — re-tracked to N

The ticket's own open question was *"Check whether the other frontends have the
same latent ordering hazard or only NilPy does."* Measured, not reasoned:

**Pascal — no hazard.** A method body typed against a class whose members are
declared BELOW it resolves correctly, including through a forward class
(`TB = class;`) and two hops (`b.a.b.v`), and matches FPC 3.2.2 exactly. Type
INFERENCE — the specific thing that breaks in NilPy, where inference runs while
every class still has zero fields — also works: under `--auto-locals`, `t := b`
and `u := b.Make` inside `TA.Infer` infer correctly from a field and from a
record-returning method of a class declared below, and the program answers 107
(7 + 100), the right value. That is expected rather than lucky: pxx PRE-SCANS
declarations, which is exactly why the FPC seed canary exists (FPC does not
pre-scan, so a dropped `forward;` breaks only the seed build).

**C — no hazard.** `struct B;` forward, `struct A` holding a `struct B *`,
`struct B` completed after it, a function walking `x->b->a->b->v`, and
`sizeof(struct B)` — all match a gcc-built oracle (peek=14, size=16). C's own
declare-before-use rule means a body can only name types already declared, so
the hazard is not expressible.

**So the remaining work is entirely `compiler/pyparser.inc`** —
`PyRegisterClassShells` / `PyRegisterClassMembers` ordering and the
`PyRegisterClassFieldsPrepass` patch this ticket wants to delete. That is Track
N's file, so the letter is changed to N; the file-lane is what the letters are
for. Nothing else about the ticket changes.

**If that re-track is wrong, it is wrong in one specific way:** if the intent
was a SHARED cross-frontend declaration phase in the core (rather than fixing
NilPy's ordering), it belongs back in A. The measurement says no other frontend
needs one today, so the shared version would be generality with no second
consumer — but the intent is the author's to state. Flip the letter back if so.

Nothing was edited under N. NilPy work is deferred by the current standing
instruction, so this is a hand-off with the question answered, not a start.
