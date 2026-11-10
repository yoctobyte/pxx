---
track: N
prio: 30
type: feature
---

# f-string: a nested format spec and a nested f-string

Two remaining holes after the 2026-08-09 f-string sweep (21 of 24 forms already
matched CPython exactly; the self-documenting `=` form and `!=` were the other
two and are now fixed).

## 1. A DYNAMIC format spec — `f"{n:{w}d}"`

```python
n, w = 42, 8
print(f"dynwidth {n:{w}d}|")     # CPython: `dynwidth       42|`
```

```
Unhandled exception: ValueError: unsupported format spec "{w"
```

Fails at RUN time with a named ValueError quoting the spec it could not parse —
visible, not a wrong number, which is the right failure. The spec is captured
verbatim and handed to `pyformat_of` as a string (deliberately: the spec
mini-language lives with the formatter so the parser and formatter cannot
disagree). A nested hole means the spec is no longer a constant, so it has to be
built as an expression — `pyformat_of(v, "" + pystr_of(w) + "d")` — which the
expander can do, since it already builds concatenations for the literal parts.

## 2. A nested f-string — `f"{f'{n}'}"`

```
error: expected comma or close parenthesis
```

A compile error. The hole scanner copies a quoted run verbatim so a brace inside
a string is not mistaken for a hole — which is right for an ordinary string and
wrong for an f-string, whose braces ARE holes. It needs to recurse rather than
copy.

Rarer than the spec case and, unlike it, always a compile error rather than a
run-time one.

## Gate

`make test-nilpy` + self-host byte-identical, extending
`test/test_nilpy_fstring_selfdoc.npy`'s "NOT asserted" note (which names both of
these) with the real cases, diffed against CPython.

## Done 2026-11-10

Both halves now work. The dynamic spec was done earlier (the nested hole in a
spec becomes a concatenation). The nested f-string is done now: inside a hole,
a quoted string is copied verbatim, so an inner `f'...'` came out as the
identifier `f` beside a plain string ("undefined variable (f)").
PyExpandFStrings (pylexer.inc) now notes an f-prefixed string inside a hole
and runs once more over its own output. The output is ordinary source again,
and each pass removes one level of nesting.
Test: test/test_nilpy_a_nested_fstring.py, with expected output = python3.
