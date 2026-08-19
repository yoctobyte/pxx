---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`from collections.abc import Mapping` binds NOTHING and reports `undefined variable (Mapping)` — PyImportRootIsConsumedOnly tests only the ROOT of a dotted from-import and has `collections` on its consume-and-ignore list, so the whole submodule is swallowed. This is what actually blocks the 7 corpus files on `unknown base class Mapping`; the shim alone cannot."
status: done
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


---

## RESOLVED. The fix, and the corpus moved.

`PyImportRootIsConsumedOnly` became `PyImportIsConsumedOnly(root, dotted)` and
the `collections` rule now matches the **full dotted path**:

```pascal
Result := PyImportRootHasNoBackingUnit(root) or
          (CaseEqual(root, 'collections') and CaseEqual(dotted, 'collections'));
```

**The two arms deliberately test different things**, and that is the point
rather than an inconsistency left behind — it is written into the code so the
next reader does not "fix" it. `PyImportRootHasNoBackingUnit` is keyed on the
ROOT because those roots are absent as a whole SUBTREE: there is no `typing.io`
unit either, so every submodule is equally unresolvable and consuming the lot
is right. The `collections` rule is about what ONE MODULE EXPORTS, which says
nothing whatever about its submodules, so it has to match the full path.

Checked the sibling first, as
[[bug-n-from-sys-import-fails-while-import-sys-works]] warns:
`PyImportRootPlainIsConsumedOnly` deliberately EXCLUDES `collections` so the
plain `import` spelling already reached the resolver for a submodule. This
therefore **closes** the asymmetry between the two spellings rather than
reintroducing one.

### Measured on the corpus — all 7 files moved

Same file, same include roots, only the compiler differing (pinned v357 vs a
self-hosted fixedpoint at HEAD):

| file | pinned | HEAD |
| --- | --- | --- |
| `_trie/__init__.py` | unknown base class Mapping | **OK** |
| `_trie/_base.py` | unknown base class Mapping | **OK** |
| `_trie/py.py` | unknown base class Mapping | **OK** |
| `_utils.py` | unknown base class Mapping | undefined variable (`__name__`) |
| `serializer.py` | unknown base class Mapping | undefined variable (`__name__`) |
| `treebuilders/__init__.py` | unknown base class Mapping | undefined variable (`__name__`) |
| `treewalkers/__init__.py` | unknown base class Mapping | undefined variable (`__name__`) |

**3 compile clean, 4 advance to a new and unrelated wall.** The `Mapping` row is
gone from the ladder. Track B's `mimic_collections_abc` shim is live — a
`class D(Mapping)` with `__getitem__`/`__iter__`/`__len__` now gives output
byte-identical to CPython, and the build prints
`note: collections_abc -> mimic_collections_abc (shim, subset)`.

The 4 that moved all stop at ONE site: `_utils.py:126` does
`baseModule.__name__` after `from types import ModuleType`, and `types` does not
resolve, so the attribute degrades to a bare name. Filed as
[[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]].

### Two pre-existing bugs found regression-checking the consumed arm

Both identical on `PXX_STABLE`, both unaffected by this change (which was the
point of checking):
`from collections import OrderedDict` is `undefined variable`, and
`from collections import Counter` **silently answers 0 for every key** —
[[bug-n-from-collections-import-counter-binds-something-that-always-answers-zero]]
(N, p58). The second breaks the consume rule's own promise that an unsupported
name walls VISIBLY.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
