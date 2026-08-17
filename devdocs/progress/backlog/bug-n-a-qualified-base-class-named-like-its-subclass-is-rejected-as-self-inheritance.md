---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`class Filter(base.Filter)` is refused with \"class Filter cannot inherit from itself\" — a QUALIFIED base class is compared by its last component only, so a subclass that keeps its base's name is misread as its own descendant. CPython accepts and runs it. Now the wall on three html5lib files, and the most common non-import error left in that corpus."
status: backlog
owner: unassigned
---

# A qualified base class named like its subclass is rejected as self-inheritance

- **Type:** bug (name resolution) — **Track N** (NilPy class declaration).
  Possibly shared: the qualifier is dropped somewhere between `ConsumeUnitQualifier`
  and the base-class identity check, and that check may live in `parser.inc`.
- **Found:** 2026-08-17 by frank2, measuring what was behind the wall cleared by
  [[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]].
- **Measured at:** HEAD `65d26b24c` — a native self-hosted build, not `pinned`.

## Repro — eight lines, no packages, no shims

`base.py`:

```python
class Filter(object):
    def name(self):
        return "base"
```

`prog.npy`:

```python
import base

class Filter(base.Filter):
    def name(self):
        return "derived"

print(Filter().name())
```

```
CPython: derived
pxx:     pascal26:3: error: Nil Python: class Filter cannot inherit from itself
                    — a base class must not be the class being declared, nor one
                    of its descendants
```

Rename **only the subclass** and it compiles and prints `derived`:

```python
class Other(base.Filter):   # ok
```

So the base class is fine, the module is fine, the inheritance is fine. The only
thing that fails is the two names being spelled the same — which means the check
is comparing `Filter` against `Filter` after having thrown the `base.` away.

## Why it matters

Re-exporting a base under its own name is ordinary Python, and html5lib does it
throughout: `html5lib/filters/whitespace.py` is exactly `class Filter(base.Filter)`,
and so are `filters/alphabeticalattributes.py`, `filters/inject_meta_charset.py`,
`filters/lint.py`, `filters/optionaltags.py`, `filters/sanitizer.py`. In the
58-file scan of `html5lib`/`tinycss2`/`webencodings` this is the **most common
error left that is not a missing import** (3 files at the point of measurement,
and it becomes more once the module-locals cap in
[[bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow]] stops
short-circuiting them earlier).

## Note on family

This is the same shape as the bug it was found behind: a name reached through an
explicit qualifier having the qualifier ignored by a downstream check that was
written for the bare case. Worth grepping the base-class path for any other
comparison against a class name that takes the identifier without asking whether
it was qualified — `devdocs/dev/normalise-dont-special-case.md`, and the fifth
instance recorded on [[meta-a-second-paths-reimplement-the-first-paths-decisions]].

## Gate

The repro prints `derived`; `class Other(base.Filter)` keeps working; a genuine
self-inheritance (`class F(F)`) is still refused — that diagnostic exists for a
reason and must not be traded away for this. Plus `make test-nilpy` green +
self-host fixedpoint.
