# Inc/Dec intrinsic rejects non-bare-symbol lvalue actuals

- **Type:** bug (compiler — intrinsic parse)  *(filed as a feature; it is a bug)*
- **Status:** done
- **Track:** A
- **Owner:** —
- **Opened:** 2026-06-21

## Reframe

Filed as "library `var`/`out` parameters accept general lvalue actuals", on the
theory that passing `rec.field` / `arr[i]` / `Self.field` to a by-ref parameter
was unsupported and `Inc` should become an RTL procedure to exercise it.

Investigation shows the broad premise is false: **general `var`/`out` lvalue
actuals already work** for user routines. A `procedure Adjust(var x: Integer)`
called with a local, a record field, an array element, an implicit-`Self` field,
and an explicit `Self.field` all pass by reference and write back correctly (test
`/tmp/vo.pas`, all five). So no RTL re-implementation of `Inc` is needed.

The real defect is narrow: the **`Inc`/`Dec` intrinsic** parsed only a bare
identifier and then expected `)`, so `Inc(rec.f)`, `Inc(arr[i])`,
`Inc(Self.field)`, `Inc(p^.f)` and the implicit-`Self` `Inc(nodes)` failed with
`Expected: )` / `undefined`. The `ParseLValueAST` call that consumes
`.field`/`[i]`/`^` selectors ran *after* the `)` was already required.

## Fix

`fix(parser): Inc/Dec accept any assignable lvalue` (e92ebd5). Parse the full
target lvalue (selectors included) before the optional step and `)`, reusing the
same `ParseLValueAST` machinery as assignment / by-ref params; drop the premature
`undefined` error so an implicit-`Self` field resolves (a true unknown still
errors). `Inc`/`Dec` stay compiler intrinsics — correct and sufficient; no
`System.Inc` RTL surface required.

## Acceptance — met

- `Inc`/`Dec` work for local / record field / array element / implicit-`Self`
  field / explicit `Self.field` / pointer-deref field, with a `,step` form.
- `examples/chess` gets past the `Inc(nodes)` blocker at `pascal26:759` (next,
  unrelated blocker is a local typed constant at `:846` — see
  `feature-local-typed-constant`).
- Negatives still reject: `Inc(x+1)` (unexpected token), `Inc(5)` (expected
  variable).
- Output-equal x86-64/i386/aarch64/arm32; self-host byte-identical; `make test`
  green (by-ref / managed-string / dynarray / `SetLength(var dynarray)` all
  still pass).

## Log

- 2026-06-21 - Opened (as a feature) after chess reached `Inc(nodes)`.
- 2026-06-21 - DONE. Reframed to a bug: general `var`/`out` lvalue actuals were
  never the problem (already work); only the `Inc`/`Dec` intrinsic parse was
  bare-symbol-only. Fixed in e92ebd5.
