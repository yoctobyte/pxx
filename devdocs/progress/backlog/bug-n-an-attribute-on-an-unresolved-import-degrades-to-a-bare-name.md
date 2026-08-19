---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`X.attr` where X came from an import that did not resolve is compiled as the BARE NAME `attr`, so `ModuleType.__name__` fails with `undefined variable (__name__)` — a message naming the attribute and never the unresolved import that caused it. Now the first wall on 4 html5lib files."
---

# An attribute on an unresolved import degrades to a bare name

```python
from types import ModuleType
print(ModuleType.__name__)     # error: undefined variable (__name__)
```

`types` does not resolve, so `ModuleType` binds to nothing — and instead of
saying so, the qualified `ModuleType.__name__` is compiled as if `__name__`
were a bare name in scope. The diagnostic then names the ATTRIBUTE and never
mentions the import that actually failed, which is the whole cost: the message
points at the wrong line.

Contrast, same build, which is what shows it is the unresolved-base path and
not `__name__` itself:

| shape | result |
| --- | --- |
| `class K: pass` then `K.__name__` | `K` — correct |
| module-level `__name__` | `__main__` — works |
| `import sys` then `sys.__name__` | a clean runtime error that NAMES the unresolved import |
| **`from types import ModuleType` then `ModuleType.__name__`** | **`undefined variable (__name__)`** |

The `sys` arm is the model to follow: it fails, but it says *"this build has no
`sys.__name__`: the import it came from could not be resolved"*. That is the
message the `types` arm should give too. Same concept, two paths, and the
second one is the broken one —
`devdocs/dev/normalise-dont-special-case.md`.

## Why it matters now

It is the first wall on **4 html5lib files** (`_utils.py`, `serializer.py`,
`treebuilders/__init__.py`, `treewalkers/__init__.py`), all reaching it through
the single site `_utils.py:126`:

```python
name = "_%s_factory" % baseModule.__name__
```

They arrived here by moving PAST `unknown base class Mapping` when
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]
was fixed — so this is the next rung, not a regression.

## Note on scope

Two fixes are available and they are not alternatives. **The diagnostic** should
name the unresolved import (cheap, and it is what makes the next such wall
self-explaining). **The behaviour** — whether `types.ModuleType` should resolve
at all — is a separate question about how much of `types` NilPy models. Do the
diagnostic first; it is what turns every future instance of this shape from a
misleading message into a correct one.

## Provenance

Found 2026-08-19 by frankonpiler-an while measuring the corpus effect of the
`collections.abc` import fix. Reproduces on `PXX_STABLE` as well once the
`Mapping` wall is out of the way.
