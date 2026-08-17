---
track: N
prio: 55
type: bug
blocked-by: [bug-a-a-python-module-s-identity-is-its-name-not-its-file]
summary: "`from .inner import X` (RELATIVE) where `inner` is a subpackage directory fails with `no unit named inner`, while the absolute `from pkg.inner import X` works — so directory-as-module resolution exists and the relative form just hands the resolver a bare name instead of the package-qualified one. html5lib has three real subpackages (_trie, treebuilders, treewalkers), so this is its next rung."
status: blocked
owner: frank2
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

---

## MEASURED 2026-08-17 — the same naming defect ALSO runs a module TWICE

Found while confirming the narrowing above, and it is worse than the resolution
failure this ticket was filed for. **The two spellings do not merely disagree
about whether a name resolves — they compile the same file as two separate
units, so its module-level code executes twice.**

```
pkg/sub.py        print("sub-init-ran")
                  X = 5
pkg/__init__.py   from .sub import X
                  P = X
main.npy          from pkg import P
                  from pkg.sub import X
                  print(P, X)
```

| | output |
| --- | --- |
| CPython | `sub-init-ran` **once**, then `5 5` |
| pxx | `sub-init-ran` **TWICE**, then `5 5` |

The relative spelling resolves `sub.py` to a unit named `sub`; the dotted
spelling resolves the same file to `pkg_sub`. Two unit rows, two compilations,
two initialisers.

### Why this is the more serious half

Python guarantees a module body runs **exactly once** — `sys.modules` is a cache,
and real code depends on it: module-level singletons, registry population
(`codecs.register(...)`, exactly what webencodings does), connection setup,
`_initialised = True` guards. Running it twice gives:

- duplicated side effects (a registry gains every entry twice);
- **two distinct copies of every class in the module**, so an object made by one
  copy fails `isinstance` against the other — the silent-wrong-answer shape,
  and precisely the divergence
  `devdocs/dev/nilpy-semantics-divergences.md` calls out as a genuine bug rather
  than a laxity (a program CPython accepts and runs can observe it);
- module-level state silently forked into two copies.

The printed `5 5` is correct, which is what makes it expensive: the observable
answer looks right while the module ran twice.

### It is one root cause, not two tickets

Both symptoms are the same defect — **the relative form does not compose its
level with the current package, so it names a unit the absolute form spells
differently.** Fixing the naming fixes the resolution failure AND the double
execution, which is the `root-cause-over-microfix.md` case: the deeper fix
deletes a case rather than adding one, and turns both symptoms green at once.

So the fix is NOT "teach the resolver about directories" (it already knows —
measured above). It is to make the relative spelling produce the same unit name
the absolute spelling produces, and to let one file map to exactly one unit.

### Check when fixing

- the module body must run **once** in the repro above;
- one file must yield one unit under BOTH spellings, mixed in the same program;
- a class from that module must satisfy `isinstance` regardless of which
  spelling imported it — add this, it is the assertion that catches a partial
  fix.

## BLOCKED 2026-08-17 — both halves are Track A's file, filed and handed up

Traced to the end and stopped at the lane boundary rather than crossing it.
Filed as [[bug-a-a-python-module-s-identity-is-its-name-not-its-file]].

The Track N side (`pyparser.inc`) **cannot** fix this alone, and that was
checked rather than assumed:

- composing the relative name needs the current module's own **unmangled**
  dotted identity, and no per-unit record of it exists — `pkg_sub` is ambiguous
  between package `pkg_sub` and module `sub` in package `pkg`;
- deriving it from `CurUnitDir` relative to `SourceFileDir` breaks under `-Fu`,
  where the package root is a `PasUnitDir` instead. That is a guess, so it was
  not made.

Both real fix points are in `parser.inc`: the compiled-unit dedupe key
(`guardIdx`, ~:33385) which is a NAME and should be the resolved FILE, and the
sibling probe (:33489) which never tries `<CurUnitDir>/<name>/__init__.py`
although `PyTryPackageSource` already implements that form — it is simply not
called with `CurUnitDir`.

**This ticket stays for the `.npy` coverage**, which is Track N's to write once
the A fix lands: the count-asserting test (a module appending to a list on
import, importer asserting length 1 after importing it by both spellings) plus
an `isinstance`-across-spellings check. Do not write it as an output-comparison
test — the probe's visible output was already correct while the module ran twice.
