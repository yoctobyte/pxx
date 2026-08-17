---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from .inner import X` (RELATIVE) where `inner` is a subpackage directory fails with `no unit named inner`, while the absolute `from pkg.inner import X` works — so directory-as-module resolution exists and the relative form just hands the resolver a bare name instead of the package-qualified one. html5lib has three real subpackages (_trie, treebuilders, treewalkers), so this is its next rung."
---

# A subpackage DIRECTORY does not resolve as a module

- **Type:** bug (NilPy frontend, module resolution) — **Track N**.
- **Found:** 2026-08-17 by a two-level probe written to check
  [[bug-n-relative-import-from-a-package-is-not-parsed]]'s `from ..pkg import X`
  form. The two-level *relative* spelling was not the variable — the failure is
  that the target is a directory.

## Repro

```
pkg/top.py            TOP = 100
pkg/inner/__init__.py from ..top import TOP
                      IN = TOP
pkg/__init__.py       from .inner import IN
main.npy              from pkg import IN
                      print(IN)
```

| | |
| --- | --- |
| CPython | `100` |
| pxx | `pascal26:3: error: import: no unit named inner and no shim mimic_inner` |

## The control that names the variable

Replace the `inner/` **directory** with a plain `inner.py` **file** and the same
import resolves and runs. So `from .X import Y` is fine; what is missing is that
`X` may be a DIRECTORY whose `__init__.py` is the module — the same
package-is-a-directory rule that the TOP-level package already implements
(`-Fu <parent>` finds `pkg/__init__.py` and compiles it; measured in
[[bug-n-relative-import-from-a-package-is-not-parsed]]).

So the mechanism exists at one level and is not applied at the next. That is the
`normalise-dont-special-case.md` smell again, and probably the cheap version of
it: one resolver path knows "directory + `__init__.py` = module", another does
not.

## Why it matters — it is html5lib's next rung

`html5lib` ships three real subpackages — `_trie/`, `treebuilders/`,
`treewalkers/` — and its own `__init__.py` reaches into them. `tinycss2` and
`webencodings` are flat and will not show this, so the ladder meets it exactly
one library up. Nothing in the fetched corpora is deeper than two levels.

Not urgent for `webencodings`, which is why it is filed rather than fixed: that
library is flat, and its remaining wall is `codecs.CodecInfo` (Track B).

## NARROWED, same day — the ABSOLUTE dotted form already works

Measured at `f5d1aac37`, and it shrinks this ticket considerably. The scope note
below guessed that `PyConsumeDottedModule` might already handle it. It does:

| spelling | result |
| --- | --- |
| `from pkg.inner import IN` (absolute dotted, `inner/` a DIRECTORY) | **works** — `42` |
| `from pkg.mod import X` (absolute dotted, a plain module — control) | works |
| `from .inner import IN` (relative, same directory) | `no unit named inner` |

And note what the working case proves: the subpackage's OWN `from .mod import X`
inside `inner/__init__.py` resolves fine. So directory-as-module resolution is
**not missing** — the whole mechanism is there and reachable.

So the title overstates it. The defect is that the RELATIVE spelling hands the
bare name `inner` to the resolver with no package prefix, where the absolute
spelling hands it the underscore-joined `pkg_inner` the resolver wants. Two
spellings of one import producing different names for the same unit — the
`normalise-dont-special-case.md` shape, and the narrow fix is to make the
relative form compose its level with the current package and then join the
absolute path, rather than teaching the resolver anything new.

That is also what [[bug-n-relative-import-from-a-package-is-not-parsed]]'s own
scope notes predicted the shape would be ("translate a level-N relative name to
the absolute one before handing it to the existing resolver"). The one-level
case worked without that translation only because a sibling MODULE's bare name
happens to already be the right unit name; a subpackage's is not.

## Scope note (superseded by the measurement above, kept for the reasoning)

Check both spellings when fixing, since they are separate call paths on today's
evidence: `from .inner import X` (relative) and `from pkg.inner import X`
(absolute dotted). The absolute dotted form was NOT measured here — it may
already work through `PyConsumeDottedModule`'s underscore-joined unit name, and
if it does, that is a hint about where the relative path should join it.

## Gate

`make compiler/pascal26` + the repro above answering `100`, + the flat-file
control still working, then `tools/gate.sh quick` **before committing** so the
FPC seed canary runs. Add the two-level case to
`test/test_nilpy_relative_import_in_package.npy`, which today stops at one level
for exactly this reason.

Stretch check: `html5lib/__init__.py` gets past its subpackage imports.
