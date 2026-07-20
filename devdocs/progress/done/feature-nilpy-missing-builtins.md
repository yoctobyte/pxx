---
track: N
prio: 45
type: feature
---

# NilPy: the remaining missing builtins — min/max, list(), reversed(), enumerate(), hex()

Swept 2026-07-20 against CPython. All of these fail LOUDLY ("undefined
variable"), which is why they are one low-priority ticket rather than
several: none of them can produce a wrong answer, unlike
[[bug-a-nilpy-int-of-string-returns-a-pointer]] found in the same sweep.

| builtin | uforth sites | shape |
| --- | --- | --- |
| ~~`min` / `max`~~ | 7 + 7 | **DONE c49064af** — two-argument only |
| ~~`list(x)`~~ | 21 | **DONE 3bc993ef** — overloads over a list or a str |
| ~~`reversed(x)`~~ | 7 | **DONE 3bc993ef** — the reversed COPY, not a lazy iterator |
| ~~`enumerate(x)`~~ | 4 | **DONE 3bc993ef** — rides the two-name for target |
| ~~`hex(n)`~~ | 1 | **DONE 3bc993ef** |

## What already works, for the record

`len`, `abs`, `ord`, `chr`, `isinstance`, `int` of a NUMBER, `str` of a
number, `//`, `%`, `/`, unary minus. `**` is absent and has ZERO uforth
sites, so it is not worth doing for this corpus.

## Shape

`min` / `max` / `list` / `hex` are plain pylib FUNCTIONS — neither name is a
Pascal keyword, so they resolve through the normal call path with no frontend
hook, the same way `bytearray` and `bytes` do (6468ff22). That makes them a
half-hour of work between them.

`reversed` and `enumerate` are not: both are iterator protocols in Python, and
NilPy's `for` is a counted-loop desugar with no iterator concept. Either give
`for` a second desugar for each of them (cheap, closed-world) or wait for a
real iterator model. `enumerate` additionally needs tuple unpacking to be
worth anything.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.

## Log

- 2026-07-20 — all remaining builtins landed (3bc993ef), regression test
  `test/test_nilpy_builtins_list_enum.npy` in `make test-nilpy`, every line
  diffed against CPython.
- `reversed()` deliberately yields a reversed COPY rather than CPython's lazy
  iterator, so `print(reversed(xs))` prints a list where CPython prints
  `<list_reverseiterator …>`. Wrapping in `list()` — which is what real code
  does — is identical. Noted here rather than filed: giving NilPy an iterator
  protocol is a much larger design question than this ticket.
- `enumerate()` over a STR is refused with a clear message: it tripped an
  unrelated pre-existing lowering gap. `enumerate(list(s))` works and is tested.
- Found while doing this, filed separately (pre-existing, confirmed on a build
  from committed HEAD with this work reverted):
  [[bug-a-nilpy-int-times-variant-in-sum-not-lowered]] — `total = total + 2 * v`
  with a for-in variant does not lower.
- 2026-07-20 — resolved, commit 3bc993ef.
