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

## Resolution (2026-06-25, v56)

Fixed. The string-compare path in `ir_codegen.inc` was gated on `(op = tkEq) or
(op = tkNeq)` only; ordering ops fell through to the general integer `else` which
did `cmp rax, rcx` on the raw string **handles** (pointers), not contents — hence
constant/garbage results.

- `symtab.inc`: new `EmitAnsiStrCmp3Reg(op, lhsTk, rhsTk)` — reuses the
  EmitAnsiStrCmpReg loading prologue (handles both tyAnsiString `[rax-8]`/nil and
  tyString `[rax]`+8 layouts per side), then min-length `repe cmpsb` with a
  length tie-break and an **unsigned** setcc (setb/setbe/seta/setae).
- `ir_codegen.inc`: ordering branch (`tkLt/tkLe/tkGt/tkGe`) when both operands are
  tyAnsiString/tyString routes to the new helper.
- Regression: `test/test_string_ordering.pas` under `make test` (greater/less/
  equal/prefix/empty cases for all six relops).
- Self-host byte-identical; `make stabilize` + `make pin` → v56.

Scope note: char-vs-string *ordering* (rare, not in ticket) still falls through;
the eq/neq char-vs-string paths are unchanged and correct.
