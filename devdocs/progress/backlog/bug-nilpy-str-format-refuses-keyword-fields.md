---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`\"{k}\".format(k=3)` fails to compile as `undefined variable (k)`, and `.format(**d)` as `expected expression`. Positional `.format()` handles zero to eight arguments; the NAMED field form is refused outright."
---

# `.format()` refuses keyword fields

```python
print("{k}".format(k=3))          # pascal26: error: undefined variable (k)
d = {"k": 3}
print("{k}".format(**d))          # pascal26: error: expected expression
```

Loud, and the message blames the caller's own code — `k` is a field name, not a
variable. Measured 2026-08-15 by a CPython differential sweep of formatting.
Everything else in that sweep agreed: `"{}"`, `"{0}{1}{0}"`, `"{:>5.2f}"`,
`"{!r}"`, `%`-formatting with a tuple and with a dict, and f-strings including
nested specs.

## Where

`PyParseStrMethod`'s `-6` case parses one to eight POSITIONAL arguments and
routes them to `pystr_format` / `format2` / `formatn`, with the substitution
itself in one place (`PyFormatApply`). Nothing parses `name=value` there, so the
name is read as an expression and fails to resolve.

## Shape of a fix

The format string is a LITERAL at almost every real call site, so the cheapest
correct fix is a compile-time rewrite: collect the keyword arguments in order,
replace each `{name...}` field in the literal with `{i...}` (preserving the
`!r`/`:spec` tail), and hand the values to the existing positional path. No
runtime change, no ABI change, and the eight-argument ceiling and its
"use an f-string" message carry over unchanged.

Two cases the rewrite cannot serve, and both should refuse LOUDLY rather than
guess: a non-literal format string with keyword arguments, and `**d`, whose keys
are not known until run time. Point both at the f-string, as the arity ceiling
already does.

Mixed positional and keyword (`"{}{k}".format(1, k=2)`) must keep CPython's
numbering: the positional fields count only the positional arguments.

## Gate

`.npy` diffed against CPython: one and several keyword fields; a repeated field
(`"{k}{k}"`); keyword fields with a spec and with `!r`; mixed positional and
keyword; a keyword field named like a Python keyword; and the refusals for
`**d` and a non-literal format string. Every existing positional row unchanged.
