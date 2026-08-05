---
owner: agent-ap-night4
---

# `<` `>` `<=` `>=` between a string and a Char compare LENGTHS, not content

- **Type:** bug — Track P (Pascal frontend); lowering, so the fix may land on
  Track A ground
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, `tools/fpc_diff_probe.sh` `str-order` case.
- **prio:** 85

## Symptom — silent wrong values, no error anywhere

```pascal
var c: Char; s: string;
...
s := 'a';  c := 'z';   s < c     { FPC: TRUE   pxx: FALSE }
s := 'ab'; c := 'b';   s < c     { FPC: TRUE   pxx: FALSE }
s := 'ab'; c := 'b';   s >= c    { FPC: FALSE  pxx: TRUE  }
```

## The rule pxx actually implements

Measured across 25 cases (both operand orders, all four relational operators,
empty/1/2/3-character strings, and cases where content and length order
*differently*), every result fits exactly one rule:

> the comparison is `Length(s)` against `1`

i.e. the `Char` operand contributes its **length** rather than being promoted to
a one-character string. The content of neither operand is examined.

| expression | lengths | pxx | rule predicts | FPC |
| --- | --- | --- | --- | --- |
| `'a' < c'z'` | 1 vs 1 | FALSE | 1<1 = FALSE | TRUE |
| `'z' < c'a'` | 1 vs 1 | FALSE | 1<1 = FALSE | FALSE |
| `'ab' < c'b'` | 2 vs 1 | FALSE | 2<1 = FALSE | TRUE |
| `'aa' < c'z'` | 2 vs 1 | FALSE | 2<1 = FALSE | TRUE |
| `'' < c'z'` | 0 vs 1 | TRUE | 0<1 = TRUE | TRUE |
| `'ab' <= c'b'` | 2 vs 1 | FALSE | 2<=1 = FALSE | TRUE |
| `'ab' >= c'b'` | 2 vs 1 | TRUE | 2>=1 = TRUE | FALSE |

It sometimes agrees with FPC by coincidence (whenever length ordering and
content ordering happen to point the same way), which is why it went unnoticed:
`'zzz' < 'b'` is FALSE under both rules.

## What is NOT affected — measured, not assumed

- **`=` and `<>` are correct** in the mixed case (`'ab' = 'b'` is FALSE,
  `'b' = 'b'` is TRUE). Only the four *ordering* operators are wrong.
- **string vs string is correct** in every case tried, including
  differing lengths (`'ab' < 'b'` with both sides string variables is TRUE).
- **Char vs Char is correct.**

So it is exactly the mixed pair, and only for ordering.

## Why this is filed urgent

1. **Silent.** No error, no warning — the expensive class described in the
   debugging playbook: a plausible wrong value far from the cause.
2. **The idiom is everywhere.** `if s > 'a'`, `if line[1] < '0'` style guards,
   and any comparison against a single-quoted one-character literal — which in
   Pascal is a `Char`, not a string, so ordinary-looking code lands here without
   the author ever thinking about types.
3. **It corrupts sorts.** Any comparator that compares a string against a Char
   orders by length, producing a stable, confident, wrong order.

## Repro

```
printf "program o; var c: Char; s: string; begin s:='ab'; c:='b'; writeln(s<c); end.\n" > /tmp/o.pas
./stable_linux_amd64/default/pinned /tmp/o.pas /tmp/o_p && /tmp/o_p    # FALSE, FPC says TRUE
```

## Suggested first look

The string-vs-string path is right and the mixed path is wrong, so the promotion
of a `Char` operand to a string is missing in the relational lowering while it is
present in the equality lowering — comparing the two lowering sites is likely
the whole diagnosis. `PXXDBG=a.ir:<proc>` will show which operands the compare
actually receives; per the playbook, print it rather than infer it.

## Coverage note

`tools/fpc_diff_probe.sh` has a `char-vs-str` case that passed throughout — it
only tested `=` and `Char < Char`, both of which are correct. The `str-order`
case that caught this uses literals. Whoever fixes it should assert all four
ordering operators in both operand orders.

## Log
- 2026-08-05 — resolved, commit 4ccc07383.
