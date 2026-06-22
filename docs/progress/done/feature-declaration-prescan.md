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
- 2026-06-22 — **DONE** (Track A). Implemented the pre-scan as a two-pass over the
  **program** declaration section in `ParseProgram` (`compiler/parser.inc`):
  - **Pass 1** (`PreScanPass := True`): the existing decl loop runs normally —
    `uses`/`var`/`const`/`type` are parsed for real (so every type/const/var name
    is registered) — but each top-level `procedure`/`function`/`constructor`/
    `destructor` registers only its **header** (the existing forward path, reused
    via `(CurTok.Kind = tkForward) or InInterface or PreScanPass`) and its body is
    skipped by the new `PreScanSkipRoutineBody` (balanced begin/case/try/asm/end
    counter, recursing into nested routines). Each subroutine's token span is
    recorded in `DeclItemStart/End`. `generic`/`specialize`/`operator` definitions
    emit in place (they rewrite the token stream) so `PreScanPass` is cleared
    around them.
  - **Pass 2**: replays the recorded spans (`TokPos := DeclItemStart[i]; Next;
    ParseSubroutine`) to emit the bodies — now with the whole section visible.
    Methods (`methOwnerCi >= 0`) are not header-registered in pass 1 (they resolve
    through the class method table built from the type section); only their body
    is skipped.
  - `ParseUnit` saves/clears `PreScanPass` so a used unit keeps its normal
    single-pass behaviour (its interface is already forward-visible; the leak
    otherwise made `PreScanSkipRoutineBody` eat the `implementation` keyword).
  - Globals: `PreScanPass`, `DeclItemStart/End[MAX_DECL_ITEMS=32768]`,
    `DeclItemCount` (`defs.inc`); initialised in `compiler.pas`.
  - Acceptance `test/test_forward_use.pas` (call-before-define, const/type
    before declaration, mutual recursion with no `forward`) — wired into
    `make test-core`; passes on the self-hosted compiler.
  - Gate: `make test` green; self-host **byte-identical** (1-gen reseed via
    `make bootstrap`); threadsafe self-host byte-identical; i386/aarch64/arm32
    build the full compiler; riscv32/xtensa ESP programs build.
  - Generic-method specialization at program top level (token-stream mutation
    during pass 2) is untested — none in the gate.
- 2026-06-22 — follow-up: unit **implementation** sections now pre-scanned too
  (`ParseUnit`), scoped per unit. Same two-pass over the `doneImp` loop: pass 1
  registers impl-private headers (the interface routines were already registered
  in the interface loop) and skips bodies; pass 2 replays them. So an impl-only
  helper may be called before it is defined and mutual recursion needs no
  `forward`. The recorded spans use a region of the shared `DeclItem` arrays based
  at the caller's `DeclItemCount` (`savedBase`), restored on exit, so nested
  `uses` (recursive `ParseUnit`) and the enclosing program's spans never clobber
  each other. `initialization` runs in full (`PreScanPass` cleared). Interface
  section is unchanged (already forward-visible). Acceptance
  `test/{unit_impl_fwd,test_unit_impl_fwd}.pas` (public→private-after,
  private mutual recursion, private const-before-use) wired into `make test-core`.
  Gate re-run green; self-host byte-identical; cross + ESP build.
