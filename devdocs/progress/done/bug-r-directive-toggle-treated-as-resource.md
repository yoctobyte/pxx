# `{$R-}` / `{$R+}` range-check toggle misread as a resource directive

- **Type:** bug (lexer / directive parsing) — blocks at emit
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-synapse-compile-check]] — `synacode.pas:50` is `{$R-}`;
  exposed once synacode started passing semantics (Move/IntToHex/StringOfChar
  landed), so it now reaches emit.

## Symptom

`{$R-}` and `{$R+}` are the **range-check** compiler switches (like `{$Q-}`,
`{$I-}`). PXX's `{$R}` handler treats *everything* after `R` as a **resource
filename**, so `{$R-}` registers a pending resource named `-`, and at emit time:

```
error: resource file not found or empty: -
```

Minimal repro:
```pascal
program p;
{$R-}
begin end.
```
→ `error: resource file not found or empty: - ()`

Scope (only `{$R}` is affected — the sibling toggles disambiguate `+`/`-`
correctly):

| directive | result |
|-----------|--------|
| `{$R-}` / `{$R+}` | **broken** (treated as resource `-` / `+`) |
| `{$Q-}` `{$I-}` `{$H+}` | OK |

The error surfaces at **emit** (`compiler/resources_emit.inc:52`), not lexing, so
it was masked until now: any earlier compile error (e.g. `synacode` stopping on
an undefined `Move`) halted before emit. Now that synacode resolves, it reaches
emit and trips.

## Root cause

`compiler/lexer.inc:1194`:
```pascal
if CaseEqual(command, 'R') and PasDirectiveActive then
  ReadPasDirectiveFile(fname);
```
Unconditional — it never checks whether the char immediately after `R` is `+`/`-`
(the range-check toggle form). Latent since `fd1c3b4` (2026-05-30, "Phase 4:
embedded resources"); not a v50 regression.

## Fix

In the `{$R}` branch, if the next non-space char is `+` or `-` (and the directive
body is just that toggle, optionally followed by `}`), treat it as the
range-check switch — a no-op like `{$Q±}`/`{$I±}` — and do **not** call
`ReadPasDirectiveFile` / register a resource. Only the `{$R name file}` /
`{$R *.res}` forms register a resource. (FPC also has `{$R+}`/`{$R-}` vs
`{$R filename}`; same disambiguation.)

## Done when

- `{$R-}` / `{$R+}` compile as no-op range switches (no pending resource, no emit
  error); `{$R name file}` still links a resource.
- `synacode` gets past emit (next gap, if any, is a genuine RTL/codegen one).
- Regression test under `make test` (a program with `{$R-}` builds and runs).
- Self-host fixedpoint byte-identical.

## Log
- 2026-06-24 — FIXED (Track A). lexer.inc {$R} branch now skips resource handling
  when the directive body begins with +/- (the range-check toggle {$R+}/{$R-}),
  treating it as a no-op like {$Q±}/{$I±}; only `{$R name file}` / `{$R *.res}`
  register a resource. Regression test/test_r_directive.pas in make test.
  Self-host fixedpoint byte-identical.
