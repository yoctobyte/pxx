---
track: N
prio: 45
type: feature
blocked-by: []
---

# `--no-type-inference`: compile a NilPy program fully dynamically

**Decided by the user, 2026-08-10.** Default stays ON (infer and specialise).
Turning it off makes every value a variant, and the programmer pays the
performance penalty knowingly.

> "let's make that a compiler switch, defaults to true. if programmer turns it
> off, pay performance penalty. and utterly cheap for use." — user

## Why

NilPy infers a static type where it can prove one and falls back to a variant
where it cannot (see [[feature-nilpy-class-as-a-value]] for the family of
whole-module "dirty" scans that decide this). That is the right default and it
is where the speed comes from.

The escape hatch is for the project that defeats the analysis wholesale — one
that loads code at run time and mutates its own object model, so nothing is
provably monomorphic. Today such a program hits refusals and specialisation
mismatches one at a time; the switch lets it say once, up front, "do not try".

The user's own framing of the boundary: this is an edge case, and a program
that genuinely needs `eval` over arbitrary input should use CPython. The switch
exists so the *nearly*-dynamic project has an answer that is not "port away".

## Naming

`--no-type-inference`, matching the existing negative-switch family in
`compiler/compiler.pas`: `--no-map`, `--no-signals`, `--no-div-check`,
`--no-strict-ir`, `--no-shims`, `--no-auto-var`, `--no-lazy-var`. Alternative if
a frontend-namespaced name is preferred later: `--nilpy-dynamic`. The flag is
inherently NilPy-only — a Pascal or C program has declared types, so there is
nothing to switch off.

## Why it is cheap — this is the point

There is no new code path. NilPy already HAS the all-variant path; it is the
fallback taken whenever a proof fails, and it is gated by the existing suite.
The switch simply forces the fallback everywhere by making the dirty-scan family
answer True unconditionally:

- `PyDefUsedAsValue`
- `PyMethodUsedAsValue`
- `PyDynAttrEverAssigned`
- `PyClassUsedAsValue` (when [[feature-nilpy-class-as-a-value]] lands)

One flag consulted at the top of each. Anything more than that is a sign the
"variant fallback" is less universal than believed, which is itself worth
knowing.

## The second reason to build it: a differential oracle

With the switch, the SAME program compiles two ways that must produce
**identical output** — specialised, and fully dynamic. That is a bug-finding
mode, not just a compatibility knob, and this frontend has a documented history
of exactly the divergence it would catch: the static and variant operand paths
taking different arms (type checks live in the runtime variant helpers, and a
both-static binop skips them — see
`project_nilpy_static_vs_variant_operand_paths_diverge`).

Running the whole `.npy` suite under `--no-type-inference` and diffing against
the normal run is a cheap sweep that needs no new expectations: any difference
is a bug in one of the two paths. Worth wiring into Track T's tiers once it
works.

## Gate

`make test-nilpy` green in BOTH modes, and the two modes producing identical
output across the suite (that diff IS the interesting result). Self-host
byte-identical — the switch touches no Pascal path.
