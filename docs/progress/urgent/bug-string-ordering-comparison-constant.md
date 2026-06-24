# AnsiString `<` `>` `<=` `>=` return constants, not a real comparison

- **Type:** bug (codegen) — silent wrong result
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** Classes ([[feature-own-net-http-lib]]) — `TStringList.Sort`.

## Symptom

Ordering comparisons on `AnsiString` ignore the operands and return a fixed
value: `>` and `>=` are **always False**, `<` and `<=` are **always True**.
`=` / `<>` work correctly.

```pascal
var a, b: AnsiString;
begin
  a := 'b'; b := 'a';            { a > b is true }
  writeln(Ord(a > b));           { prints 0 — should be 1 }
  writeln(Ord(a < b));           { prints 1 — should be 0 }
  writeln(Ord(a >= b));          { prints 0 — should be 1 }
  writeln(Ord(a <= b));          { prints 1 — should be 0 }
  writeln(Ord(a = b));           { prints 0 — correct }
end.
```

Every operand pair gives the same `> = 0`, `< = 1` — including equal strings
(`'abc' < 'abc'` returns 1) and prefixes. So the comparison is not evaluating the
lexicographic order at all; it looks like the string-compare lowering for the
ordering operators yields a constant (or never calls the comparator / discards
its result), while `=`/`<>` use a separate, correct path.

## Impact

Breaks every string sort, ordered insert, and range/threshold test on strings —
e.g. `TStringList.Sort` (uses `FList[j].FStr > tmp.FStr`) does not order. Also
any `if name < other` logic.

## Likely area

The relational-operator lowering for managed strings: `=`/`<>` map to a
byte-equality/length path (correct), but `<`/`<=`/`>`/`>=` likely don't reach a
3-way `CompareStr`-style comparator, or its result/sign is dropped. Compare the
codegen for string `=` vs string `<`.

## Done when

- All six relops on AnsiString evaluate true lexicographic order (`'b' > 'a'`,
  `'apple' < 'apply'`, `'abc' = 'abc'`, prefix `'ab' < 'abc'`, etc.).
- Regression test under `make test` covering `< <= > >= = <>` with greater/less/
  equal/prefix cases.
- Self-host fixedpoint byte-identical; `make stabilize` + `make pin` so
  `TStringList.Sort` ([[feature-own-net-http-lib]]) re-enables.
