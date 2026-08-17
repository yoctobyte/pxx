---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from .sub import NAME` — an intra-package relative import — fails with `error: undefined variable (from)`. Plain `from pkg import NAME` parses fine; the leading dot is what breaks. This blocks ALL FOUR Python corpora (webencodings, tinycss2, html5lib, reportlab), because every real package uses relative imports in its __init__.py."
---

# A relative import (`from .sub import X`) is not parsed

- **Type:** bug (NilPy frontend, import parsing) — **Track N**.
- **Found:** 2026-08-17, first contact with a third-party corpus while working
  [[feature-nilpy-thirdparty-libraries-as-targets]]. `webencodings/__init__.py:19`
  is `from .labels import LABELS` and the compile stops there.

## Repro — five lines, no third-party code

```
pkg/sub.py        VALUE = 7
pkg/__init__.py   from .sub import VALUE
main.npy          from pkg import VALUE
                  print(VALUE)
```

```sh
python3 main.npy                      # 7
./compiler/pascal26 main.npy m        # pascal26:1: error: undefined variable (from)
                                      #   near: end  end   from >>>  sub
```

Plain `from pkg import VALUE` parses. The **leading dot** is what is not
handled — the parser appears to fall out of import handling and try to evaluate
`from` as an expression, which is why the message names `from` as an undefined
variable rather than mentioning imports at all.

## Why this is the first rung, ahead of wiring any Makefile target

An intra-package relative import in `__init__.py` is how essentially every real
Python distribution is laid out. **All four fetched corpora hit it**, so a
corpus target wired today would only assert this same parse error. Nothing
further about NilPy's third-party readiness can be measured until it works.

## Module resolution itself is NOT the problem — record this before re-deriving it

The obvious first guess (and mine) was that pxx could not find the package at
all. It can:

```sh
./compiler/pascal26 -Fu/abs/path/to/library_candidates/webencodings drv.npy drv
```

resolves `from webencodings import ...` and **begins compiling the package's
`__init__.py`**. `sys.path.insert(...)` does nothing, correctly — that is a
runtime mechanism and pxx resolves imports at compile time. Note `-Fu` is absent
from the compiler's usage line, which is what makes this easy to miss.

## Scope notes for whoever fixes it

- CPython spells several forms: `from . import name`, `from .mod import name`,
  `from ..pkg import name` (parent), and `import .mod` is NOT valid Python — so
  only the `from`-forms need to parse.
- The dot count is a *level*, resolved against the importing module's own
  package directory. Since resolution already works through `-Fu`, the likely
  shape is to translate a level-N relative name to the absolute one before
  handing it to the existing resolver, rather than teaching the resolver
  anything new.
- Check the sibling form `from . import lookup` too — `webencodings/tests.py`
  uses exactly that, so it is needed for the corpus's own test suite even after
  `__init__.py` compiles.

Likely `compiler/pyparser.inc` (import handling), which is Track N's file — but
**check before assuming**: if the resolver end lives in `parser.inc` that half
is Track A and must be filed, not edited.

## Gate

`make compiler/pascal26` + the five-line repro above answering `7`, plus
`from . import X` and a two-level `from ..pkg import X`, then
`tools/gate.sh quick` **before committing** so the FPC seed canary runs.
Stretch check that actually matters: `webencodings/__init__.py` compiles past
line 19.
