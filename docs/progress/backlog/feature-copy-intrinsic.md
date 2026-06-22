# `Copy` as a generic overloaded intrinsic (string + dynarray families)

- **Type:** feature (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, while delivering string `Copy` in lib)
- **Relation:** pairs with the lib `strutils` work (`lib/rtl/strutils.pas` already
  ships the interim AnsiString `Copy`); depends on **generics or builtin-overload
  support**. Sibling of the same-shape intrinsics `Delete` / `Insert` / `Concat`
  (see note below).

## Why the lib cannot finish this

`lib/rtl/strutils.pas` provides `Copy(s: AnsiString; index, count): AnsiString`
— good enough for the demos that copy substrings, and soon to be
`SetLength`-optimized (build the result once, no char-by-char append). But the
full FPC `Copy` is a **generic intrinsic overloaded over a type family**, which a
single non-generic RTL function cannot express:

1. **dynamic-array `Copy(arr, index, count)` → sub-array of `array of T`.** The
   real blocker: element-type-aware, generic over `T`. Not writable as one
   concrete RTL routine. Needs generics or a compiler intrinsic.
2. **2-arg form `Copy(s, index)`** = from `index` to the end (count defaults to
   the rest). Overload resolution on arity.
3. **string-family overloads:** `ShortString`, `UnicodeString` / `WideString`
   (if/when those types exist).
4. **call-site resolution by argument type:** pick the string vs dynarray
   meaning of `Copy` from the actual argument type.

## Scope

- Recognize `Copy` as an overloaded intrinsic resolved at the call site by
  argument type (string family vs dynamic array) and arity (2-arg vs 3-arg).
- dynarray form returns a fresh `array of T` (element-type-aware copy).
- Keep the lib `strutils.Copy(AnsiString)` working as the interim path; the
  intrinsic supersedes it for the generic cases.

## Siblings (same reasoning — mention so they aren't re-discovered)

`Delete(s/arr, index, count)`, `Insert(src, dst, index)`, and `Concat(...)` are
also intrinsics overloaded over the same string + dynarray families. They will
hit the identical "can't be one non-generic RTL function" wall. Fold them into
this work (or spin a sibling ticket) rather than re-filing each from a demo.

## Log
- 2026-06-19 — opened by track B. Interim AnsiString `Copy` lives in
  `lib/rtl/strutils.pas`; this ticket covers the generic intrinsic the lib can't
  express (dynarray `Copy`, 2-arg form, string-family overloads, by-type
  resolution).

## Progress (2026-06-19) — dynamic-array Copy DONE

The real blocker (generic dynamic-array `Copy(arr, index, count)` → fresh
`array of T`, element-type-aware) is implemented, plus the 2-arg
`Copy(arr, index)` form and call-site resolution by argument type:

- New `AN_DYN_COPY` node. The intrinsic fires only when the first argument is a
  dynamic array; a string `Copy` keeps the `sysutils.Copy` RTL path (resolved
  whether or not a `Copy` proc is in scope — handled both at the no-Copy-proc
  factor point and at the no-overload-match point, so a string `Copy` is never
  shadowed).
- Lowered (ir.inc) into: clamp the count to the source bounds (`PXXClampLen`),
  SetLength a fresh dyn-array local of the source element type, then raw-copy
  `count*elemSize` bytes from `source[index]` (`PXXMemCopy`). Element size comes
  from the source symbol, so it is generic over `T` (validated for Integer and a
  24-byte record). Index is 0-based (FPC dynamic-array Copy).

Validated x86-64 (test-core, `test/test_dynarray_copy.pas`) + arm32 cross suite;
self-host + cross-bootstrap byte-identical. NOTE: a raw byte copy, so an array of
a *managed* element type (AnsiString / managed record) is shallow — deep element
copy is a later extension.

Landmines recorded: a bare runtime-helper call whose result is unused is NOT
emitted (only statement-linked nodes are) — store the result into a temp; and the
result must be tagged so the assignment stores the full 8-byte handle.

Remaining: string-family overloads beyond the RTL `Copy` (ShortString /
UnicodeString), and the dynarray `Delete`/`Insert`/`Concat` variants. On
i386/aarch64 `b := Copy(...)` is additionally blocked by a separate pre-existing
whole-dynamic-array assignment gap (`bug-dynarray-whole-var-assign-cross`).

## Progress (2026-06-20) — string Delete / Insert / Concat in sysutils

The AnsiString `Delete`, `Insert`, and `Concat` siblings are now in
`lib/rtl/sysutils.pas` as pure-Pascal library functions (not compiler
intrinsics). Design decision: `Copy` stays compiler-owned (it has intercept
entanglements with `Str`); `Delete`/`Insert`/`Concat` are library-side since
the compiler doesn't depend on them internally.

- `procedure Delete(var s: AnsiString; index, count: Integer)` — FPC-compatible
  no-op on out-of-range or non-positive count; count clamped to end of string.
- `procedure Insert(const src: AnsiString; var dst: AnsiString; index: Integer)`
  — FPC-compatible: index < 1 → 1, index > Length+1 → append, empty src → no-op.
- `function Concat(const s1, s2: AnsiString): AnsiString` — 2-arg wrapper over
  `+`. Variadic Concat can't be expressed in this compiler; `+` chains for more.

All three tested in `test/lib_sysutils.pas` with golden-output verification
(`make lib-test`). Remaining scope under this ticket: the **dynarray**
variants of Delete/Insert/Concat (these need compiler intrinsics, same as
dynarray Copy), and string-family overloads for ShortString/UnicodeString.

- 2026-06-22 — **string `Delete` / `Insert` DONE** (the most-wanted siblings).
  Both were missing entirely (`undefined variable (Delete)`). Implemented as
  statement intrinsics in ParseStatementAST that lower to builtin helpers
  `__pxxStrDelete(var s; index; count)` / `__pxxStrInsert(const src; var s;
  index)` (compiler/builtin/builtin.pas), built on `__pxxStrCopy` so managed
  refcounting is the ordinary var-param + assign path; args eval once. Available
  with no `uses` (pre-scan pulls the builtin unit on `delete(`/`insert(`); a user
  routine of the same name shadows; string dest only (dynarray Delete/Insert and
  ESP left as follow-up). Test `test/test_string_delete_insert.pas`, FPC
  oracle-matched. make test + cross-bootstrap byte-identical.
  **REMAINING:** `Concat(...)` intrinsic; string `Copy` family overloads
  (ShortString/Unicode if/when added); dynamic-array `Delete`/`Insert`; by-type
  call-site resolution polish. (2-arg `Copy(s,i)` and dynarray `Copy` already
  work.)

- 2026-06-22 — **`Concat` DONE.** `Concat(s1, ..., sn)` folds at parse time
  (ParseFactor) to chained string `+`, reusing the working concat codegen; no
  `uses`, a user `Concat` shadows it. Test `test/test_concat_intrinsic.pas`,
  FPC-matched. **REMAINING:** string `Copy` family overloads (ShortString/Unicode
  if/when added); dynamic-array `Delete`/`Insert`. The common string-mutator set
  (Copy 2-arg, dynarray Copy, Delete, Insert, Concat) is now complete.
