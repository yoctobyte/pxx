---
track: B
prio: 60
type: bug
blocked-by: []
summary: "Four sysutils gaps from one 22-program string differential against FPC 3.2.2: Concat takes exactly two AnsiStrings (FPC's is variadic and takes Chars), AnsiQuotedStr and SameStr do not exist, and the TryStr* family leaves its value untouched on failure where FPC zeroes it. Everything else in the family — Copy/Pos/Delete/Insert bounds, StringReplace, Format, Trim, comparison, PChar interop, ShortString — was byte-identical."
---

# Four sysutils string gaps

- **Type:** bug / missing entry points — Track B (`lib/rtl/sysutils.pas`).
- **Status:** backlog
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
