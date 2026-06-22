# Policy: FPC-bootstrap subset vs PXX-only library features

- **Type:** policy / architecture
- **Status:** rainy-day 
- **Owner:** —
- **Opened:** 2026-06-16

## The distinction (make it explicit)

There are two compilation worlds, with different allowed feature sets:

1. **`compiler/*` (the compiler itself)** is compiled by **both** FPC (the
   bootstrap seed) and PXX (self-host, byte-identical fixedpoint). It may only use
   the **intersection** of FPC and PXX — the restricted self-host subset. No
   classes, no sets-heavy code, no PXX-only sugar, careful `{$ifdef FPC}` use
   (`compiler.pas:213`). This is a hard constraint: anything FPC rejects, or where
   FPC and PXX diverge, cannot live here. (See [[project_fpc_define_landmine]].)

2. **`lib/*` (RTL, LCL, and units like classes/streams/collections/typeinfo)** is
   compiled **only by PXX**. It may use the **full** PXX feature set — classes,
   sets, N-D arrays, the new const/array forms, the upcoming variadic-`array of
   const` sugar and library `writeln`, the proposed `object` type, etc. FPC
   compatibility is irrelevant here.

This boundary is already real in practice (the `lib/` units use classes the
compiler can't), but it is not written down anywhere as policy. Writing it down
prevents two failure modes: (a) someone adds a PXX-only feature to `compiler.pas`
and breaks the FPC bootstrap; (b) someone avoids a perfectly good PXX feature in a
library because they think "the compiler can't use it."

## The rule

- **Editing `compiler/`?** Restrict to the FPC∩PXX subset. If unsure, it must
  compile under FPC (`make bootstrap`) AND self-host byte-identical.
- **Editing `lib/`?** Use whatever PXX supports. Only PXX compiles it.
- A PXX feature that FPC lacks or implements differently is **acceptable** — it
  just may never appear in `compiler/`.

## Why it matters / what to exploit

- Frees the libraries to be idiomatic and high-level (classes, sets, variadics,
  `object`) without dragging the compiler subset along.
- Lets us grow PXX-only language features deliberately, knowing the only
  constraint is "not in the compiler."
- Suggests a direction: move more RTL surface into PXX-only units that use the
  full feature set, keeping `compiler/` lean and subset-clean (see
  [[feedback_inc_to_units]]).

## Acceptance

- A short `docs/` policy note (or a CONTRIBUTING section) stating the two worlds
  and the rule, linked from the build docs.
- Optionally: a CI/`make` guard that flags PXX-only constructs accidentally used
  in `compiler/` (e.g. the bootstrap already catches it — document that
  `make bootstrap` failing on FPC is the canary).

## Notes

- This is mostly documentation, but it unblocks the writeln-as-library work
  (feature-writeln-as-library) and the `object` type
  (feature-object-reference-type), both of which are explicitly library-only.
