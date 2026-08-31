---
track: N
prio: 25
type: feature
---

# `match` / `case` — structural pattern matching is not parsed

```python
def classify(v):
    match v:
        case 0:
            return "zero"
        case 1 | 2:
            return "small"
        case _:
            return "big"
```

```
pascal26:2: error: undefined variable (match)
```

`match` is a SOFT keyword in Python — still usable as an ordinary identifier —
so it lexes as a name and dies at the use. Visible, not silent.

**3 of the neuzelaar corpus's 168 files.** Low, and listed so every line of that
census has a ticket behind it.

## Scope note — pick the subset deliberately

Full structural pattern matching (class patterns, mapping patterns, capture with
`as`, guards) is a large feature. Real code overwhelmingly uses the flat subset:
literal patterns, `|` alternatives, a `_` wildcard, and a bare capture name.
Landing that subset and REFUSING the rest by name is the right first step —
consistent with how the nested-unpacking forms still name themselves rather than
mis-parsing (`feature-nilpy-starred-and-nested-unpacking`).

Do NOT silently treat an unsupported pattern as a wildcard: that turns a missing
feature into a wrong answer.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over the supported
subset, plus a `{%FAIL}`-style refusal test for one unsupported pattern shape.
