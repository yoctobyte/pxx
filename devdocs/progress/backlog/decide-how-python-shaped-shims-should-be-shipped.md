---
track: U
prio: 45
type: decide
blocked-by: []
summary: "A shim whose content is Python-level aliases (six: `text_type = str`) cannot be written in the mimic_<name>.pas slot, and the working alternative — a NilPy .py in a library root — silently defeats --no-shims. Three options, recommendation is to let the shim lookup also probe mimic_<name>.py."
---

# How should a Python-SHAPED shim be shipped?

- **Track U** (decision). Raised 2026-08-17 by frank3 (Track B) from
  [[feature-nilpy-six-and-warnings-shims]], which is parked in `unfinished/`
  behind it.
- Measured on `pinned` v344.

## The fork

`six` is a file of Python-level aliases — `text_type = str`,
`string_types = (str,)`, `integer_types = (int,)`. In CPython it is itself pure
Python. Two facts collide:

1. **The shim slot is Pascal-only.** `parser.inc:33210` probes
   `lib/pcl/mimic_<name>.pas`, then `lib/rtl/mimic_<name>.pas`, and nothing
   else. Expressing "the `str` type object, as a value" from Pascal is not
   something any existing shim does.
2. **A NilPy `.py` in a library root already works** — verified, output
   byte-identical to CPython:
   ```
   from six import text_type, PY3, binary_type, unichr, viewkeys
   print(text_type("x"), PY3, unichr(65), sorted(viewkeys({"a": 1})))
   pxx / CPython:  x True A ['a']
   ```
   …**but it silently defeats `--no-shims`.** That flag exists so "a build that
   succeeds provably used no compatibility shim" (`defs.inc:1571`), and it
   refuses only the `mimic_` substitution. A `lib/**/six.py` is a real library
   module by the resolver's own rules, so it satisfies `import six` under
   `--no-shims` and falsifies exactly the guarantee the flag sells.

## Options

**A. Write `mimic_six.pas` in Pascal.** Honours `--no-shims` with no compiler
change. But it has to express Python type objects as values from Pascal, which
no shim does today, for a file whose entire content is Python aliases. Highest
friction, and the result would be the least readable file in `lib/`.

**B. Ship `lib/pcl/six.py` as a NilPy library module.** Works today, zero
compiler change, and it is what the module actually is — CPython's `six` is a
pure-Python file too. Cost: `--no-shims` stops meaning what it says, silently,
for every shim shipped this way afterwards.

**C. (recommended) Let the shim lookup also probe `mimic_<name>.py`.** A small
Track N/A change beside the existing `.pas` probes. Then a Python-shaped shim is
written in Python, lives in the shim namespace, and `--no-shims` refuses it like
any other — the flag's guarantee is preserved *by construction* rather than by
everyone remembering the convention. It also removes the standing trap in B,
where any future `lib/**/<stdlib-name>.py` quietly becomes an unrefusable shim.

## Why this is a decision and not just work

B is the path of least resistance and is *wrong in a way that is invisible*:
nothing goes red, `--no-shims` keeps exiting 0, and it simply stops proving
what it claims. That is the "the property holds and nothing enforces it" shape
this repo has hit twice this week. It should be chosen deliberately or not at
all.

## What is NOT open

The `six` content itself — the name list, its scoping to what html5lib and
tinycss2 actually import, and the `viewkeys`-is-a-function trap — is settled in
the parent ticket and is unaffected by this. Only *where the file goes*.
