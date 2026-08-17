---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`import string` then `digits = string.digits` fails with `undefined variable (digits)` — the LHS name breaks resolution of the same-named attribute on the RHS. Only for PASCAL shim modules (mimic_*.pas); a .py shim and a plain NilPy module both work. Blocks html5lib's constants.py:544, which most of html5lib imports."
---

# Assigning to a name that collides with a Pascal shim's attribute fails

- **Type:** bug (name resolution) — **Track N** (NilPy import/attribute
  resolution). May be core; filed here because the construct is a NilPy import.
  **Not fixed under B** — `mimic_string` is not missing anything.
- **Found:** 2026-08-17 by frank3, chasing the `undefined variable (digits)`
  wall on the corpus ladder.
- **Measured against:** `pinned` **v346**. Not re-checked at HEAD.

## Repro

```python
import string
digits = string.digits
print(digits)
```

```
pxx:     pascal26: error: undefined variable (digits)
CPython: 0123456789
```

Rename the target and it compiles:

```python
import string
p = string.digits      # fine
```

## The boundary, measured one variable at a time

| case | result |
| --- | --- |
| `digits = string.digits` (Pascal shim, a `const`) | **FAIL** |
| `punctuation = string.punctuation` (Pascal shim, another `const`) | **FAIL** |
| `capwords = string.capwords` (Pascal shim, a **function**) | **FAIL** |
| the same inside a `def` rather than at module level | **FAIL** |
| `p = string.digits` — different target name | ok |
| `PY3 = six.PY3` (a **.py** shim, `mimic_six.py`) | **ok** |
| `value = mymod.value` (a plain NilPy `.py` module) | **ok** |
| `print(string.digits)` with no assignment at all | ok |

So it is not about the attribute, not about const-versus-function, and not about
scope. **It is specific to a Pascal-unit shim (`mimic_*.pas`)**, and it triggers
when the assignment target has the same name as the attribute being read. The
`.py` shim route added today is unaffected, which is a useful narrowing: the two
shim kinds resolve attributes differently and only one of them has this.

The collision is with the attribute name **anywhere in the right-hand side**,
not only in a bare `X = mod.X`. The real corpus site is a call:

```python
# html5lib/constants.py:544
digits = frozenset(string.digits)
```

## Why it is worth 55

`constants.py` is imported by most of html5lib — `_tokenizer.py` does
`from .constants import digits, hexDigits, EOF` — so this one line gates a large
part of that package, and `X = module.X` is an entirely ordinary Python idiom
(`digits = string.digits`, `path = os.path`). The diagnostic also points at the
wrong thing: it names the variable being *defined*, so the natural reading is
"this name is missing" when the name is being created on that very line.

## Not a `mimic_string` gap — checked first

`lib/rtl/mimic_string.pas` already exports every public name in CPython's
`string` module except `Formatter` and `Template`: `ascii_letters`,
`ascii_lowercase`, `ascii_uppercase`, `capwords`, `digits`, `hexdigits`,
`octdigits`, `printable`, `punctuation`, `whitespace`. `print(string.digits)`
prints `0123456789` today. Nothing is missing from the shim, so nothing in
Track B fixes this.

## Gate

The repro prints `0123456789`, all four FAIL rows above become ok, and
`html5lib/constants.py` stops reporting `undefined variable (digits)`.
