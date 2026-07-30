---
track: N
prio: 80
type: bug
---

# `s[0] >= "0"` is ALWAYS False and `s[0] < "0"` ALWAYS True — a char is ordered against the literal's ADDRESS

```python
s = "5"
print(s[0] < "0", s[0] < "9", s[0] > "0", s[0] > "9")
# CPython: False True  True  False
# pxx:     True  True  False False
```

Every `<`/`<=` answers True and every `>`/`>=` answers False, **regardless of the
characters involved**. The character's code is being ordered against the string
literal's address, so the comparison never depends on the operands at all.

`==` and `!=` are correct (they are special-cased to a content compare), which
is exactly what makes this survive: the equality tests people write first all
pass.

## Why this is prio 80

It silently breaks the single most common character-scanning idiom in Python:

```python
while i < len(src) and src[i] >= "0" and src[i] <= "9":
    num = num + src[i]
    i = i + 1
```

`src[i] >= "0"` is always False, so the loop body **never runs**, the digit is
never accumulated, and the scanner silently produces wrong tokens instead of
failing. Found exactly that way — a hand-written tokenizer for `"12 + 34 * 2"`
returned `[1, 2, +, 3, 4, *, 2]` and computed `5478200` where CPython returns
`['12', '+', '34', '*', '2']` and `92`. Any lexer, digit/letter classifier,
input validator or manual parser is affected, and none of them error.

## Measured surface

| expression | CPython | pxx |
| --- | --- | --- |
| `s[0] == "5"` / `!= "5"` | True / False | True / False ✓ |
| `s[0] < "0"` | False | **True** |
| `s[0] < "9"` | True | True (right by accident) |
| `s[0] > "0"` | True | **False** |
| `s[0] > "9"` | False | False (right by accident) |
| `s[0] >= "0"` | True | **False** |
| `c = s[0]` then `c >= "0"` | True | **False** |
| `s >= "0"` (WHOLE string, not indexed) | True | True ✓ |
| `a[0] >= b[0]` (char vs CHAR) | True | True ✓ |
| `for c in s:` then `c >= "0"` | True | True ✓ |
| `ord(s[0]) >= ord("0")` | True | True ✓ |

So it is specifically **tyChar on one side and a string LITERAL on the other**,
with an ORDERING operator. Char-vs-char is fine, whole-string-vs-literal is
fine, and a for-loop variable is fine (it is a variant, which routes through
pycmp_v).

## Not a regression

Reproduced identically on the stable compiler from 2026-07-27, before any of
this session's operand work — the pre-session binary gives the same
`True True False False`. Pre-existing.

## Likely cause

pxx spells a one-character literal `tyChar`, but only sometimes — the note on
`IRNodeIsPyStr` records that "pxx spells a one-character literal tyChar, but
Python has no character type". Here one side ends up an ordinal and the other a
string POINTER, and the ordering compares them numerically: the char code
(~48-57) is always below any heap/rodata address, which is exactly the observed
all-`<`-True / all-`>`-False pattern. Equality escapes because it is routed to a
content compare first.

This is the SHAPE-BLINDSPOT family — a conversion keyed on the operand's shape
rather than its type — and the same "handle read as a number" root as
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]], which fixed the
str-vs-number pairs but not char-vs-str (both count as "str" to that
predicate, correctly, since char vs str IS legal Python).

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output, and the tokenizer program as an end-to-end case —
it must produce `['12', '+', '34', '*', '2']` and `92`. Keep the char-vs-char
and whole-string rows as guards that the working paths are untouched.

## Sibling found in the same sweep: a char DICT KEY renders unquoted

```python
s = "ab"
d = {}
d[s[0]] = 1
print(d)          # CPython: {'a': 1}     pxx: {a: 1}
```

The key is stored and looked up correctly (len is 1, the value reads back), so
this is rendering only — `pyrepr_of` has a `Char` overload that returns the bare
character where the `AnsiString` one adds quotes. Same tyChar-is-not-a-str
family as the ordering bug above, and cheap to fix alongside it.

## Log
- 2026-07-30 — resolved, commit 54f7ae5b7.
