# Latent: whole-record array-element copy in main-program body emits store no-ops

- **Type:** bug
- **Status:** blocked (cannot reproduce)
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §2 Phase 5 note)

## Update (2026-06-06)

Could **not** reproduce with a direct `arr[i] := someRecord` in the main-program
body (3-field record): prints correctly. Likely already fixed by the
record-copy>8 work (`IR_COPY_REC`), or it needs the exact historical trigger
(the `__rttireg` sentinel-drop `Fixups[]` shift). Also confirmed it is **not**
the same family as the operator-result bug (that was operator dispatch + binop
typing, commit 2cf92fb). Parking in `blocked/` until someone produces a live
repro; the worked-around path (`test/gui/repro_multiunit_rtti_segfault.pas`)
still passes.

## Symptom

A whole-record array-element copy in the **main-program body** is miscompiled by
the IR backend — the store no-ops. Surfaced during the multi-unit RTTI work: the
`__rttireg` sentinel-drop shifted `Fixups[]` with a whole-record array-element
copy, producing NULL string literals. Worked around by copying the record fields
one at a time; the **underlying codegen bug is still latent**.

## Notes

- Distinct from the already-fixed "whole-record copy truncated records > 8 bytes"
  (todo.md §4) which lowered to `IR_COPY_REC`. This one is specifically a
  record-valued array-element store in the main body that no-ops.
- Possibly the same family as
  [`bug-operator-result-inferred-var`](bug-operator-result-inferred-var.md)
  (record store dropped/short in a specific context). Confirm or separate when
  picked up.
- Regression repro on the worked-around path:
  `test/gui/repro_multiunit_rtti_segfault.pas`.

## Acceptance

A direct test that does `arr[i] := someRecord` in the main-program body
round-trips all fields without the field-by-field workaround; self-host
fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from todo.md §2 Phase 5 latent-bug note.
