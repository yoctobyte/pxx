---
track: B
prio: 60
type: bug
blocked-by: []
summary: "Four sysutils gaps from one 22-program string differential against FPC 3.2.2: Concat takes exactly two AnsiStrings (FPC's is variadic and takes Chars), AnsiQuotedStr and SameStr do not exist, and the TryStr* family leaves its value untouched on failure where FPC zeroes it. Everything else in the family — Copy/Pos/Delete/Insert bounds, StringReplace, Format, Trim, comparison, PChar interop, ShortString — was byte-identical."
owner: frank1-AN
---

# Four sysutils string gaps

- **Type:** bug / missing entry points — Track B (`lib/rtl/sysutils.pas`).
- **Status:** working
- **Opened:** 2026-08-21, from a string differential run while working Track A.

## Context first: the family is in good shape

Twenty-two programs, one per shape, each diffed against fpc 3.2.2. **Eighteen
were byte-identical**, including every row that usually hides a bug:

- `Copy` with out-of-range, zero and negative indices (six variants)
- `Pos` for a miss and for the empty needle
- `Delete` / `Insert` at 0, past the end, and with a runaway count
- `StringReplace` with `rfReplaceAll` / `rfIgnoreCase` / overlapping matches
- `Format` with width, left-align and zero-pad on `%d` and `%s`
- `Trim` / `TrimLeft` / `TrimRight` including all-space and empty input
- comparison operators and `CompareStr` / `CompareText`
- `PChar` interop, `StrLen`, indexing, round trip back to AnsiString
- `ShortString` concat, `SetLength` on a string, `StringOfChar`, char indexing

So the four below are gaps, not a pattern of rot.

## 1. `Concat` is fixed-arity and AnsiString-only

```pascal
W(Concat('a','b','c'));
```
```
pascal26:10: error: no overload of Concat matches these arguments
  argument types: (Char, Char, Char)
  candidates:
    Concat(AnsiString, AnsiString)
```

FPC's `Concat` is variadic and accepts chars. Two shapes are missing: more than
two arguments, and `Char` arguments (a `Char` does not widen to `AnsiString` at
the overload site).

## 2. `AnsiQuotedStr` does not exist

`undefined variable (AnsiQuotedStr)`. `QuotedStr` exists and is correct;
`AnsiQuotedStr(s, quoteChar)` is the general form and is what code that quotes
with anything other than `'` calls.

## 3. `SameStr` does not exist

`undefined variable (SameStr)`. `SameText` exists (case-insensitive); `SameStr`
is its case-SENSITIVE twin, i.e. `CompareStr(a, b) = 0`. One line.

## 4. `TryStr*` leaves the value untouched on failure

```pascal
i := -1;
ok := TryStrToInt('q', i);      { fpc: False 0    pxx: False -1 }
```

FPC's documentation calls the value *undefined* after a failed `Val`, so pxx is
not strictly wrong — but FPC in practice zeroes it, and a stale value surviving
a failed conversion is the shape that bites: `if not TryStrToInt(s, n) then` is
often followed by code that uses `n` anyway with a default in mind.

The whole family is declared `var value`, not `out value`, and all seven behave
the same way: `TryStrToInt`, `TryStrToInt64`, `TryStrToQWord`, `TryStrToFloat`,
`TryStrToDate`, `TryStrToTime`, `TryStrToDateTime`.

**Note:** switching the declarations to `out` would NOT fix it — pxx does not
model `out` at all (`bug-a-an-out-parameter-of-a-managed-type-is-not-cleared`),
and FPC's `out` does not clear ordinals either (measured). The fix is one
explicit `value := 0` on each failure path.

## Gate

`make lib-test` green, plus each of the four shapes above matching fpc 3.2.2.

---

## 2026-08-27 — RESOLVED. Two of the four were already fixed; the other two are done.

Re-measured every row against **fpc 3.2.2** before touching anything, which is
what stopped a wrong change from landing.

| # | ticket said | measured today |
| --- | --- | --- |
| 1 | `Concat` is fixed-arity and AnsiString-only | **already fixed, in the COMPILER** |
| 2 | `AnsiQuotedStr` does not exist | genuinely missing — **added** |
| 3 | `SameStr` does not exist | **already there**, with `AnsiSameStr` beside it |
| 4 | `TryStr*` leaves the value untouched | date/time three already cleared; the **four scalar ones did not — done** |

### 1 — and the library fix I nearly landed was the wrong one

`Concat('a','b','c')` compiles and prints `abc` today, on the fresh compiler
**and on v388 pinned**. It was fixed in `pasparser_expr.inc`
(`compat-pascal-uses-sysutils-withdraws-the-variadic-concat`): `uses sysutils`
was withdrawing the variadic intrinsic because a two-argument `Concat` was in
scope, and that arm now folds `Concat(s1..sn)` to `+` when no overload matched.

I had already written the obvious library fix — a `Concat(const args: array of
const)` overload rendering each element through `FmtArgStr` — and it worked.
**It was still wrong.** It has exactly the shape to MATCH `Concat('a','b','c')`
at the overload site, so it would divert those calls away from the intrinsic
fold into a TVarRec-building library call, and for the dynamic-array form
(`Concat(arr1, arr2)`, which the same intrinsic serves) it would silently
produce text instead of an array. Measured cost of the version I reverted: the
test binary was 498 bytes larger.

Reverted, and the test carries a comment saying why no such overload exists,
because adding one is the natural move for the next reader.

### 2 — AnsiQuotedStr, and QuotedStr rewritten as its special case

`QuotedStr` kept its own copy of the quote-doubling loop. It is now
`AnsiQuotedStr(s, '''')` — one rule, one place
(`devdocs/dev/normalise-dont-special-case.md`).

### 4 — the four scalar TryStr* now zero on failure

`TryStrToInt`, `TryStrToInt64`, `TryStrToQWord`, `TryStrToFloat`. The ticket
said all seven behaved this way; `TryStrToDate`/`Time`/`DateTime` already
cleared, with a comment saying why, so only four changed. `out` would not have
done it, for the two reasons the ticket already records.

Callers checked rather than assumed: `lib/rtl/variants.pas` reads the value only
on success, and `lib_strtoint` / `lib_strutil` assert it only inside
`TryStrToInt(...) and (v = ...)`.

### Measured

- **`test/lib_sysutils_string_gaps`** — 13 rows, expected output taken from
  **fpc 3.2.2 itself**, byte-identical. Registered in the Makefile beside
  `lib_strutil`, built with `$(PXX_STABLE) -Fulib/rtl` and verified through that
  exact path, so it needs no pin.
- The two rows that were ALREADY fixed are kept in the test. A gap that closed
  without a test is a gap that can reopen without one.
- `lib_strutil` (59 `=ok`, 0 FAIL), `lib_strtoint` (36 `=ok`),
  `lib_strutils_words` and `lib_format` all green through `$(PXX_STABLE)`, with
  the exact counts the Makefile asserts.
