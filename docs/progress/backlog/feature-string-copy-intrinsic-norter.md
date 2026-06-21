# String `Copy` as a no-RTL compiler intrinsic (bootstrap-usable)

- **Type:** feature (compiler — Track A)
- **Status:** backlog
- **Owner:** — (Track A)
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
