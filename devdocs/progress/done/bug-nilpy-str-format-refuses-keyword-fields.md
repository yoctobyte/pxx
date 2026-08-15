---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`\"{k}\".format(k=3)` fails to compile as `undefined variable (k)`, and `.format(**d)` as `expected expression`. Positional `.format()` handles zero to eight arguments; the NAMED field form is refused outright."
status: done
owner: claude-AN
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

## Resolution (2026-08-15)

The compile-time rewrite the sketch called for. The arg loop records each
`name=` in order and consumes it, so the VALUE lands in an ordinary positional
slot; after the loop `PyFormatRenumber` rewrites the LITERAL in place, mapping
each named field to `nPositional + keywordIndex`. Nothing at runtime changed,
the eight-argument ceiling and its "use an f-string" message carry over, and
every arity rung below sees an ordinary positional format string.

**Every field comes out explicitly numbered, including the auto-numbered ones.**
CPython forbids mixing automatic and manual numbering in one string, so
renumbering only the NAMED fields would have produced exactly that mix —
`"{}{k}"` becoming `"{}{1}"` — and handed the runtime a shape it is not asked
to handle. Normalising all of them keeps one shape and makes
`"{}{k}".format(1, k=2)` fall out with CPython's numbering.

Refused loudly, as the ticket asked: `.format(**mapping)` (the keys are a
run-time fact), a non-literal format string with named fields, a positional
argument after a keyword one (not valid Python either), and an unknown field
name — which names the field rather than blaming the caller's variables.

Worth recording: the helper's braces are `Chr(123)`/`Chr(125)`, never quoted
characters. **This dialect NESTS brace comments**, so a `'{'` literal opens one
and the file stops parsing hundreds of lines later as "unexpected character".
`PyParseSetComp` carries the same warning, which is where the fix came from.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN (no builtin change, so
no pin). `test/test_nilpy_str_format_keyword_fields.npy`, byte-identical to
CPython: one and several named fields, a repeated field, a spec and both `!r`
and `!s` on named fields, mixed positional and keyword, explicit indices and
auto-numbering unchanged, doubled-brace escapes, an expression as the value,
and named fields inside a method chain and a comprehension. Re-checked the
thirteen existing format tests.

Not covered, and it refuses loudly: a field with a SUBSCRIPT (`"{d[0]}"`), which
CPython allows. Small and separable — filed as a note here rather than a ticket
of its own until something asks for it.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
