---
prio: 40
---

# decide: `--rtti=none` semantics — what happens to the FUNCTIONAL parts of the RTTI blob?

- **Type:** decision — **Track U**. Blocks [[feature-opt-rtti-emit-on-use]]
  (claimed, then parked on this fork; recon done 2026-07-18 night by fable-O).

## The fork

`EmitRTTI` emits more than reflection payload. Skipping it wholesale under a
`--rtti=none` embedded flag breaks two FUNCTIONAL consumers:

1. **Class-field finalize layouts** (`UClsLayoutOff`, reached via [VMT-16]):
   destructors walk this to release managed fields (see
   project_class_field_finalize_vmt16_layout). Absent ⇒ managed class fields
   silently LEAK (or worse if the walker doesn't nil-check).
2. **ClassName backlink** ([VMT-8] → header with the interned name): the RTL
   `ClassName` reads it. Absent ⇒ garbage pointer deref unless the RTL
   nil-guards.

Reflection proper (`is`/`as`, `TypeInfo`, published props/methods, registry,
enum RTTI, streaming) can hard-ERROR at compile time under `none` — that part
is uncontroversial.

## Options

- **A. `none` = reflection-only strip.** Keep finalize layouts + the name
  backlink; drop headers' prop/meth arrays, registry, enum RTTI, published
  data. Smallest semantic surface, smaller size win (name strings remain).
- **B. `none` = full strip + RTL nil-guards.** Also drop names/backlink;
  `ClassName` returns '' (RTL nil-check), finalize layout absent ⇒ compiler
  ERRORS on managed class fields under `none` (embedded programs with managed
  class fields must not use the flag). Maximum size win, loudest failure mode.
- **C. Usage-driven only (skip the flag entirely).** Emit per-class RTTI only
  when the program provably reflects; finalize layouts always emitted (they
  are usage-driven by construction: only classes WITH managed fields get one).
  No new user-visible mode; the north-star from the parent ticket, more work.

## Recommendation (fable-O)

**C** as the destination, **A** as the cheap tonight-able step if a flag is
wanted sooner: A is safe-by-construction (functional data untouched) and
still removes the prop/meth/registry/enum payload that dominates RTTI size on
real class-using programs. B's error-on-managed-fields is a footgun for
exactly the ESP audience the flag targets.

## Also decided-needed

The classless quick win (bare program still ships a TObject name remnant) is
uncontroversial under ANY option — can land independently: skip ALL RTTI when
no user class exists AND no reflection op appears (builtin TObject row alone
does not count).
