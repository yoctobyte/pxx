---
slug: bug-t-the-wiring-census-cannot-see-a-python-package-so-py-stays-uncensused
title: "check_test_wiring.py cannot resolve a Python package, so .py stays out of SUBJECT_EXT and 140 files are uncensused"
track: T
prio: 30
type: bug
status: new
created: 2026-09-22
owner: ""
summary: "`.py` is the last test-subject extension `check_test_wiring.py` cannot see: 140 tracked files under test/, of which the Makefile compiles at least 3 directly and the rest are imported by wired .npy tests. It is NOT in SUBJECT_EXT and adding it is not a tightening -- MEASURED by doing it 2026-09-22: 55 files land in the unwired report and ALL 55 ARE FALSE POSITIVES. The mechanism is `consumed_by`, which resolves an import by matching a module name against a subject's basename STEM, and two shapes defeat that: `__init__.py`, whose stem can never equal the package name a test imports, and a dotted submodule (`platform/_gl.py` imported as `platform._gl`). The tool's own docstring says reporting real wiring \"would train people to ignore the check, which costs more than the gaps it finds\", so shipping 55 of them would break it in exactly the way it was designed not to break. FIX IS PACKAGE-AWARE RESOLUTION, not a wider extension list: a directory containing __init__.py IS the module `<dirname>`, and a dotted name resolves componentwise against directories. Do not add `.py` to SUBJECT_EXT until that lands. .bas and .rs WERE added the same day, both with a measured population of zero new failures (4321 -> 4328 -> 4358, rc=0 throughout)."
---

# What is missing

`tools/check_test_wiring.py` censuses test SUBJECTS by extension.
`SUBJECT_EXT` now reads `.pas .npy .c .lua .fth .bas .rs`. `.py` is not there,
and 140 tracked files under `test/` end in it.

They are not all fixtures. `grep -c 'COMPILER) .*test/.*\.py' Makefile` answers
**3**, so at least three are compiled as subjects in their own right; the rest
are modules that a wired `.npy` imports, which is legitimate wiring the tool
already knows how to follow for other languages.

# Why it is not a one-line fix, measured rather than argued

Adding `.py` to the tuple and re-running, 2026-09-22:

```
scanned 4498 test subject(s)
55 test file(s) NOT referenced by any build rule or tools/ script
```

**All 55 are false positives.** They are `__init__.py` files and package
submodules under `test/nilpy_*/`, `test/dualspell/`, and similar. Two distinct
shapes, one cause:

1. **`__init__.py`.** `consumed_by` builds `stem[basename-without-extension]`
   and matches an import name against it. A test writing `import nilpy_deadarm`
   names the DIRECTORY; the file that satisfies it is `__init__.py`, whose stem
   is `__init__` and matches nothing, ever.
2. **A dotted submodule.** `test/nilpy_emptyinit/platform/_gl.py` is imported as
   `platform._gl`. The stem map holds `_gl`, the import pass produces
   `platform._gl`, and the two never meet.

The tool's own comment on `consumed_by` says why this matters more than the
gaps it would close:

> Both are "something runs it", which is the question. Reporting them would
> train people to ignore the check, which costs more than the gaps it finds.

A check that reds on 55 correctly-wired files on its first outside run teaches
that it can be ignored. That is the same failure CLAUDE.md records for a guard
that is born red.

# The fix

Package-aware resolution in `consumed_by`, not a wider `SUBJECT_EXT`:

- a directory containing `__init__.py` **is** the module named by that
  directory, so an import of `<dir>` reaches `<dir>/__init__.py`;
- a dotted name resolves componentwise against directories, so
  `platform._gl` reaches `platform/_gl.py` relative to the importing file;
- a relative import (`from . import x`) resolves against the importer's own
  package.

Then add `.py` and re-measure. **The acceptance test is that the unwired list
is EMPTY or every entry on it is a genuine gap** — not that the number got
smaller.

# How this was found, which is the part worth copying

Not by suspicion. `.bas` was added to `SUBJECT_EXT` an hour earlier, and the
finding there was that **the scanned-subject count moved by less than the
number of files I had just added** — arithmetic, needing no doubt about the
population at all, in the one run where the discrepancy is still attributable
to the person who caused it.

Then the same seat wrote "the gap was `.bas`" having measured only `.bas`.
One census of what actually lands under `test/`
(`git log --diff-filter=A --name-only --since='30 days ago'`) answered the
quantifier: `.pas` 1257, `.expected` 675, `.npy` 329, `.c` 241, **`.py` 108**,
`.sh` 50, **`.rs` 21**, `.bas` 4. The extension found first was the smallest of
the three real gaps, and it was found first only because somebody happened to
add one.
