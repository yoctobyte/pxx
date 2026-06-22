# `{$mode delphi}` — remaining @-relax edge slices

- **Type:** feature (dialect mode, follow-up)
- **Status:** rainy-day (low priority)
- **Owner:** — (Track A)
- **Opened:** 2026-06-22
- **Follows:** [[feature-mode-delphi]] (core slices DONE — done/)
- **Driver:** [[feature-mimic-fpc]] / [[feature-networking]] — a **proper Synapse
  library compile** is the real test. Pull a slice in here only when a concrete
  Synapse (or other real `{$mode delphi}` source) unit actually trips on it; file
  the offending construct as the trigger. Do **not** speculatively build these
  out — they are edge bind sites the headline deltas already cover for the
  common cases.

## Why low priority

The two FPC-verified behavioural deltas and the bind sites that carry real
library weight are already done and oracle-matched against FPC `-Mdelphi`:

- `@`-optional procedural value at the **assignment** site (`p := F`).
- `@`-optional procedural value at the **call-argument** site (`g(F)`).
- `@`-optional **method pointer** at the assignment site (`p := obj.M`).
- bare own-name read is never the result var in delphi (paramless → recursive
  call; with-params → function value).

What remains are narrower constructs. They mostly *parse to a wrong-but-rare
shape* rather than mis-compile silently, so they surface loudly when hit. Hold
until Synapse (or similar) demands them.

## Remaining slices

1. **Proc-value comparison** `if p = F` / `if p <> F` (and `@F` on either side
   of a relational op). A bare routine name compared to a proc-typed expression
   should take its address. Weaker footing than the bind sites: needs the LHS
   proc-type known at the point the RHS is parsed (`ParseExpr`, the
   `tkEq/tkNeq/...` branch ~parser.inc 4304), and there is **no overload-retry
   harness** there as there is for call args — so the paramless-function
   ambiguity (call-first vs address) has to be resolved differently (likely:
   only relax when one side is unambiguously proc-typed and the other is a bare
   routine name that cannot be a value-call here — procedure / with-params fn,
   the `TryDelphiBareProcArg` rule). FPC `-Mdelphi` is the oracle.

2. **Proc-typed / method-pointer record & array fields** as the bind target:
   `rec.cb := F`, `arr[i] := obj.M`. The current assignment-site relax keys off a
   simple lvalue var symbol (`idx` with `SymProcSig[idx] >= 0`,
   `TypeKind = tyRecord` for method ptr). A field/element lvalue goes through a
   different node (`AN_FIELD`/`AN_INDEX`) and is not covered. Need to detect the
   target's element/field proc-sig and reuse the same `AN_PROCADDR` /
   `AN_METHODREF` emission.

3. **Method pointer at the call-arg site** `g(obj.M)` — only the *assignment*
   site does method pointers today. Mirror the `TryDelphiBareProcArg` peek for
   the `obj.method` shape (emit `AN_METHODREF`), gated on the formal being a
   method-pointer parameter.

4. **Per-unit / per-section `{$mode}` reset.** `DelphiMode` is currently a
   whole-compile flag (set by the lexer directive, never restored). Fine for a
   single delphi program, but in a multi-unit compile a non-delphi unit pulled
   after a delphi one would **inherit** delphi semantics. Needs save/restore of
   `DelphiMode` around `ParseUsesUnit` / unit boundaries (same shape the
   [[feature-mimic-fpc]] v2 per-unit define scoping will want — coordinate).
   **This is the one that bites silently in a real multi-unit Synapse build**, so
   it is the most likely first trigger.

## Implementation pointers (already in tree)

- Assignment-site relax + method-ptr branch: `compiler/parser.inc`, search
  *"Delphi-mode @-optional procedural value"*.
- Call-arg relax: `TryDelphiBareProcArg` + `MatchCallDelphiProcAddr` (same file).
- Method-pointer infra: `AN_METHODREF`, `EnsureMethodPtrRec`, `of object` types,
  target-aware TMethod Data offset in `AN_ASSIGN` (`compiler/ir.inc`).
- Distinguisher: a method-pointer var/field is `TypeKind = tyRecord` (16-byte
  Code+Data); a plain proc-ptr is `tyPointer`. `SymProcSig >= 0` = proc-typed.
- Oracle: `fpc -Mdelphi`. Gate any change: `make test` (self-host byte-identical)
  + `make cross-bootstrap`.

## Gate / landmines

- `}` inside a `{ }` comment closes it early (cost a test once — use `Code+Data`,
  not `{Code,Data}`).
- Never default `DelphiMode` on; `lib/rtl` must stay `{$ifdef FPC}`-clean.
