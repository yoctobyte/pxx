---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`from collections.abc import Mapping` binds NOTHING and reports `undefined variable (Mapping)` — PyImportRootIsConsumedOnly tests only the ROOT of a dotted from-import and has `collections` on its consume-and-ignore list, so the whole submodule is swallowed. This is what actually blocks the 7 corpus files on `unknown base class Mapping`; the shim alone cannot."
---

# `from collections.abc import ...` is swallowed by the `collections` root rule

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]].
**This ticket, not the shim, is what unblocks the corpus.**

Measured on **pinned v356** (`2bb09afb0cff`):

```python
from collections.abc import Mapping
print(Mapping)
```

| | |
| --- | --- |
| CPython | `<class 'collections.abc.Mapping'>` |
| pxx (pinned v356) | `error: undefined variable (Mapping)` |

`import collections.abc as cabc` **does** reach the shim (the resolver prints
`note: collections_abc -> mimic_collections_abc (shim, subset)`), so the shim
itself is fine — it is the `from`-form that never gets there.

## Root cause

`PyImportRootIsConsumedOnly` (`compiler/pyparser.inc:33003`) decides whether a
from-import should be consumed and ignored, and it tests only the **root** of the
dotted name. `collections` is on that list (because `from collections import
OrderedDict` was meant to be absorbed), so `collections.abc` matches too and the
whole import is swallowed — binding nothing, or `None`.

Contrast that proves it is the root rule and not module resolution: `from
xml.etree.ElementTree import Element` works and prints its shim note, because
`xml` is not on the consumed list.

The fix is to test the **full dotted path**, not the root — or to resolve the
submodule first and only fall back to the consume rule when nothing resolves.

## Why it matters

7 of 48 corpus files stop at `unknown base class Mapping`
(`html5lib/_utils.py`, `_trie/{__init__,_base,py}.py`, `serializer.py`,
`treebuilders/__init__.py`, `treewalkers/__init__.py`), and every one of them
writes `from collections.abc import Mapping`. The Track B shim
`lib/rtl/mimic_collections_abc.py` is landed and differential-tested against
CPython, but it moves **zero** of those files until this is fixed, because that
spelling never reaches it.
