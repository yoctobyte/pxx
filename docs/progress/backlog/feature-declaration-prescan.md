# Declaration pre-scan — whole-section symbol visibility (kill declare-before-use)

- **Type:** feature (parser architecture / FPC-compat)
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-21
- **Relation:** the principled fix for the self-host declaration-order strictness
  noted in [[bug-bare-function-name-call-vs-resultvar]] (the `LowerCase`-used-
  before-its-definition trap). Companion to [[feature-fpc-vs-pxx-feature-boundary]].

## Problem

PXX resolves identifiers in a single forward pass, so a routine/type/const must
be **declared before use**. FPC (and Delphi) give whole-section visibility: in a
unit's `implementation`, or a program body, any routine may call any other
regardless of source order, and mutual recursion needs no manual `forward`.

Concretely: a helper near the top of `parser.inc` that calls `LowerCase`
(defined ~6000 lines later in the same compilation) compiles under the FPC seed
(whole-unit resolution) but fails self-host with
`error: undefined variable (LowerCase)`. We currently dodge this by hand —
ordering callees before callers and sprinkling `forward` — which is fragile and
a standing FPC-source-compat gap.

## Why pre-scan, not lazy-linking

Two ways to get order-independence:

- **Lazy-linking** (emit a fixup on an unknown name, resolve at section end).
  This is what the *backend* already does for forward jumps/labels. At the
  *semantic* level it is worse: a call site needs the callee's **signature now**
  — for overload resolution, argument type-checking, by-ref/`const` param
  marshalling, and the return type. A deferred symbol gives a name but no shape,
  so you would be back-patching types after the fact. Type-unsafe and messy.
- **Pre-scan / two-pass over declarations** (recommended). Pass 1 walks the
  top-level declarations and registers every routine **header** (full signature),
  plus type/const/var names, with bodies skipped. Pass 2 parses the bodies with
  everything already visible. Signatures are known up front, so overload/type
  resolution at a call is unchanged. This is exactly how FPC gives free ordering
  and `forward`-free mutual recursion.

## Scope

- A header-registration pass over each top-level declaration scope: the program
  body and (separately) a unit's `implementation` section. Register proc/func
  signatures (name, params with by-ref/const/array/dyn flags, return type, method
  owner), type names, and const/var names — without parsing bodies.
- Pass 2 = the existing body parse, now with the symbol table pre-populated.
- Reuse what already exists: unit **interface** sections are already forward-
  visible (a manual pre-scan), and the C-header importer pre-scans declarations.
  Generalise the interface-header registration to the implementation/program body.
- Nested routines keep lexical (inner-after-outer) scoping; the pre-scan is for
  the top level of a section, matching FPC.

## Non-goals

- Changing body codegen or the symbol-table representation.
- Out-of-order *variable initialisation* semantics (still top-to-bottom at run
  time); this is purely name *visibility*.

## Payoff

- Deletes a class of self-host-only "undefined variable" failures and the manual
  ordering/`forward` discipline in the compiler's own source.
- Real FPC-source compatibility for mutually-recursive routines without `forward`
  (helps `feature-mimic-fpc` and any imported FPC RTL/library source).

## Acceptance

- `test/test_forward_use.pas`: routine A calls routine B defined *after* it (no
  `forward`); a const/type used before its declaration; mutual recursion A<->B.
  Compiles and runs correctly.
- Existing `forward` declarations still work (no double-registration).
- `make test` green; self-host **byte-identical** (a parser-structure change is a
  1-gen reseed, [[feedback_codegen_reseed_not_nondeterminism]]); cross
  (i386/aarch64/arm32) + ESP still build.
- After landing, optionally remove a now-unnecessary `forward`/ordering hack in
  compiler source as a proof point (separate small commit).

## Landmines

- Param-symbol slots are reused across procs ([[project_interfaces_corba_complete_2026_06_19]]);
  the pre-scan must record signatures via the stable parallel arrays
  (`ProcParamRecId` etc.), not transient `Syms[].RecName`.
- The seed (FPC) masks the order-dependence, so validate on the **self-hosted**
  `compiler/pascal26` after `make bootstrap`, never the FPC-built seed — same
  trap as [[bug-bare-function-name-call-vs-resultvar]].

## Log
- 2026-06-21 — filed (Track A), split out of the bare-function-name divergence
  bug as the principled fix for declaration-order strictness.
