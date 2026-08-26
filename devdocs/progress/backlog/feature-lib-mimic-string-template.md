---
track: B
prio: 12
type: feature
blocked-by: []
summary: "string.Template — the $-placeholder class (substitute, safe_substitute) — is the one member of Python's string module still missing, and it is what logging/__init__.py uses. Deliberately NOT urgent: `import logging` does not resolve at all today, so nothing can reach Template until a logging shim exists. Split out of feature-lib-mimic-string, which shipped every constant and both capwords forms."
---

# `string.Template` — the `$`-placeholder class

- **Type:** feature (library) — **Track B** (`lib/rtl/mimic_string.pas`).
- Split out of [[feature-lib-mimic-string]] on 2026-08-15, which closed with
  every constant and both `capwords` forms matching CPython 3.12. `Template` is
  the remainder.

## Why it is prio 15 and not higher

It is the member the stdlib actually uses — `logging/__init__.py` is the only
one of the ten `string`-importing stdlib modules that reaches past the
constants, and it reaches for `Template`. But **`import logging` does not
resolve at all today**:

```
error: import: no unit named logging and no shim mimic_logging
```

So nothing can reach `Template` until a `logging` shim exists, and writing it
first is building the second storey. Sequence it behind that; raise the prio the
moment `logging` lands.

Directly-written `string.Template` in application code is rare — it is the
`$name` templating class most people skip in favour of f-strings or `.format()`.

## Surface

```python
t = string.Template('$who likes $what')
t.substitute(who='tim', what='kung pao')      # raises KeyError if missing
t.safe_substitute(who='tim')                  # leaves '$what' in place
```

- `$$` is a literal `$`.
- `$name` and `${name}` are both placeholders; `${name}` is what makes
  `${noun}ification` work.
- An identifier is `[_a-z][_a-z0-9]*`, case-insensitive.
- `substitute` raises `KeyError` for a missing key and `ValueError` for a
  malformed placeholder; `safe_substitute` raises **neither** and leaves the
  original text.
- Class attributes `delimiter` and `idpattern` are overridable in CPython —
  almost certainly out of scope for a first cut, but say so explicitly rather
  than leaving it ambiguous.

## Note for whoever takes it

Derive the behaviour from a CPython diff, not from the docs — the
`feature-lib-mimic-string` close is a worked example of why: `capwords(s, sep)`
looked like a variation of `capwords(s)` and is a different function, and three
of five edge cases would have shipped wrong from the plausible reading.

## Gate

A `.npy` diffed against CPython 3.12: `substitute` and `safe_substitute`, `$$`,
`$name`, `${name}`, `${name}` adjacent to text, a missing key on both methods, a
malformed placeholder on both, and a non-identifier after `$`. Build with
`$(PXX_STABLE)`; do not rebuild the compiler.
