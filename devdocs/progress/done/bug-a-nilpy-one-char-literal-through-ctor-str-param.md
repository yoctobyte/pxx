---
track: A
prio: 70
type: bug
---

# NilPy: a ONE-character literal through a ctor `str` param becomes a char — silent, then segfaults

Found 2026-07-20 while landing [[bug-nilpy-method-returning-str-garbage]].
**Independent of it**: reproduces with no method involved, and a plain `def`
with the same parameter type handles it correctly.

## Repro

```python
class W:
    def __init__(self, n: str) -> None:
        self.n = n

a = W("x")
print(a.n)          # CPython x  -> pxx SEGFAULT

b = W("xyz")
print(b.n)          # CPython xyz -> pxx xyz   (multi-char is fine)
```

A `def` is NOT affected, which is the tell:

```python
def g(n: str) -> None:
    print(n)
g("x")              # correct
```

## Cause

pxx types a one-character literal `"x"` as `tyChar` — Python has no character
type, so to NilPy that is a `str` of length 1. The `def` parameter path already
widens it; the CTOR parameter / field path does not, so the field ends up
holding the character CODE (0x78) where a string handle is expected. Using it
then dereferences 120 as a pointer:

    mov (%rax),%rdi     ; rax = 0x78

Same tyChar-vs-str family as the `int("0")` case fixed in 62c4e457 (which
returned the character code 48) and the `"a" * 3` handling in a123c875. Worth
fixing as the family rather than one site: **audit every place a NilPy value
crosses into a `str` context and confirm tyChar widens.**

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, both repros above
matching CPython, plus a sweep of one-character strings through: ctor param,
def param, method param, field assignment, list/dict element, return value,
concatenation and comparison.

## Log

- 2026-07-20 — fixed at the ROOT the ticket asked for: a 1-character literal is
  no longer a char in NilPy at all (da66e43d), rather than widening it at each
  crossing. Filed separately as
  [[bug-a-nilpy-one-char-string-literal-is-a-char]] before this duplicate was
  spotted; both describe the same defect.
- The sweep this ticket asks for was run against CPython and passes: ctor param,
  def param, method param, field assignment and re-assignment, list/dict
  element, return value, concatenation, comparison, repeat, `in`, `int()`,
  `str()`, `ord()`, `chr()`, str methods, `+=`. Regression test:
  `test/test_nilpy_one_char_string.npy` in `make test-nilpy`.
- One unrelated gap surfaced by the sweep and filed on its own:
  [[bug-a-nilpy-print-of-a-list-prints-a-pointer]].
- 2026-07-20 — resolved, commit da66e43d.
