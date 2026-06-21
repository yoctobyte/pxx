# String `Copy` as a no-RTL compiler intrinsic (bootstrap-usable)

- **Type:** feature (compiler — Track A)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21 (recurring: hit again writing `{$IF DECLARED}` in lexer.inc)
- **Relation:** complements `feature-copy-intrinsic` (that one made the *dynarray*
  `Copy` a compiler intrinsic and keeps *string* `Copy` in the RTL —
  `lib/rtl/strutils.pas` / `lib/rtl/sysutils.pas`). This ticket is the missing
  half: string `Copy` is unavailable to compiler-internal / no-`uses` / frozen-only
  code, because that code does not (and must not) `uses sysutils`.

## Problem (recurring)

Substring `Copy(s, index, count)` exists only as an RTL library function. The
self-hosting compiler source cannot call it — `compiler/*` does not import the
RTL — so every time compiler-internal code wants a substring it errors:

```text
pascal26: error: Copy: dynamic-array Copy needs a dynamic-array first argument
                 (string Copy needs the strutils/sysutils unit)
```

We have now hit this at least twice:
- writing `PasCondNameDeclared` in `lexer.inc` (last-component of a dotted name) —
  worked around with an `AppendChar` char-by-char loop;
- earlier RTL-dialect work (see `project_rtl_dialect_landmines`).

The `AppendChar`-loop workaround is fine once but it keeps recurring, and it is
exactly the kind of primitive that should be free everywhere (like `Length`,
`SetLength`, `Ord`, `Chr`) with no unit import.

## Decision needed — compiler vs library vs mixed

Recommendation: **mixed, biased compiler.** Make the primitive substring
`Copy(s, index, count)` (and the 2-arg `Copy(s, index)` rest-of-string form) a
**compiler intrinsic** on the string families it can lower without help —
frozen `string` and managed `AnsiString` — so it is available with zero `uses`,
including in the compiler's own bootstrap. The RTL `strutils`/`sysutils.Copy`
becomes a thin pass-through (or is superseded) for user code; higher-level
string helpers (`Trim`, padding, search) stay in the library.

- Must not shadow or break the existing string-`Copy` intercept entanglements
  with `Str` noted in `feature-copy-intrinsic`.
- Must self-host: the intrinsic has to lower under the frozen string model the
  compiler is built with, byte-identical, no reseed surprises (a codegen change
  reseeds once — that is expected, not non-determinism).
- 1-based index, FPC semantics (clamp count to end; out-of-range → empty),
  matching the current RTL `Copy`.

## Acceptance

- A frozen-string program with **no `uses`** compiles `s2 := Copy(s, 2, 3);`
  and prints the right substring.
- The compiler source itself can use `Copy(str, i, n)` (convert the `lexer.inc`
  `PasCondNameDeclared` last-component loop to `Copy` as the canary) and still
  self-host byte-identical.
- Existing `lib_sysutils` / `lib_strutils` golden tests stay green; user-facing
  string `Copy` behavior unchanged.
- dynarray `Copy` (already an intrinsic) is unaffected.

## Log
- 2026-06-21 — filed. Recurring papercut: string `Copy` is RTL-only, so
  compiler-internal / no-RTL code cannot use it and falls back to `AppendChar`
  loops. Hit while implementing `{$IF DECLARED}` (`d35e47c`).
- 2026-06-21 — DONE (commit dd706ff; mixed, biased compiler — the user-accepted
  "odd but fine" solution). The substring primitive `__pxxStrCopy(const s; index, count)` lives in
  the always-injectable `builtin` unit (`compiler/builtin/builtin.pas`, the managed-
  AnsiString home next to StrInt/FloatToStr) — body is the proven `r := r + s[i]`
  loop, so the AnsiString return uses the standard managed-result path (no manual
  refcount). Bare `Copy(s, index[, count])` on a string with no `Copy` proc in scope
  lowers to an `AN_CALL` of it (parser.inc, beside the dynarray-Copy intrinsic); the
  pre-scan pulls `builtin` on any non-ESP `Copy(`. The dynarray `Copy` intrinsic and
  the explicit `uses sysutils` overload (`procIdx >= 0` path) are untouched — string
  overloads beyond the primitive stay library-side as planned.
  - Acceptance: no-`uses` `Copy(s,i,n)` substring — PASS (1-/2-/3-arg, index & count
    clamping; `test/test_string_copy_intrinsic.pas` in `make test-core`). Existing
    `test_dynarray_copy` + explicit `uses sysutils` Copy still green. self-host +
    threadsafe byte-identical.
  - LANDMINE: the 2-arg form passes count = MaxInt as the "rest" sentinel, so
    `index + count - 1` overflowed Integer → empty result; fixed by capping count to
    `n - index + 1` BEFORE forming `last`.
  - DEFERRED: the compiler-source canary (convert the lexer.inc `__pxxStrCopy`-
    /`PasCondNameDeclared` AppendChar loop to `Copy`) is NOT done here — it would
    make the compiler build newly pull `builtin`, perturbing the self-host baseline;
    do it deliberately as its own change if/when wanted. Frozen-only/ESP code still
    can't use string `Copy` (builtin is non-ESP), matching the prior reach.
