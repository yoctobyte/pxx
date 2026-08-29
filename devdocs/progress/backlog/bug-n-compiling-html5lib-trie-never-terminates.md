---
track: N
prio: 55
type: bug
blocked-by: []
summary: "Compiling library_candidates/html5lib/html5lib/_trie/__init__.py — five lines — never terminates. Found as a pxx process that had been in state R for 1 day 16:47 on a six-session box, and reproduced bounded: `timeout 60` returns 124 after emitting only the shim-resolution notes. No diagnostic, no progress, no exit."
---

# Compiling html5lib's `_trie/__init__.py` never terminates

Found 2026-08-29 by frankB. Not found by running the corpus — found because a
`ps` while diagnosing something else showed a pxx process from this checkout in
state **R** with `ELAPSED 1-16:47:23`, burning a full core continuously on a box
where six sessions were contending for cores.

## The input is five lines

```python
from __future__ import absolute_import, division, unicode_literals

from .py import Trie

__all__ = ["Trie"]
```

109 bytes. Reproduced bounded rather than inferred from the old process:

```
timeout 60 stable_linux_amd64/default/pinned \
  -Fulibrary_candidates/html5lib -Fulibrary_candidates/html5lib/html5lib -Fulib/rtl \
  library_candidates/html5lib/html5lib/_trie/__init__.py /tmp/out
-> rc=124
```

All it emits first is module resolution getting under way:

```
note: six -> mimic_six (shim, subset)
note: bisect -> mimic_bisect (shim, subset)
note: collections_abc -> mimic_collections_abc (shim, subset)
```

Then nothing. No diagnostic, no partial output, no exit — which is the worst
shape for a corpus driver, because a hang has no line number to bisect from and
nothing distinguishes it from a slow compile until someone looks at a clock.

## What was ruled out, measured not reasoned

The obvious hypothesis was the **module named `py`** — `from .py import Trie`
resolving a relative module whose filename is `py.py`, which an importer that
strips `.py` extensions could loop on. **Wrong.** A minimal package with
`pkg/py.py` and `pkg/__init__.py` containing `from .py import Trie` compiles in
well under a second, and so does the same shape with the module renamed
`other`. Recorded because it is the first thing the next reader will try.

## The chain, for whoever picks it up

`_trie/__init__.py` → `_trie/py.py` → `six`, `bisect`, and `._base`
→ `_base.py`, whose body is:

```python
try:
    from collections.abc import Mapping
except ImportError:  # Python 2.7
    from collections import Mapping
```

and `py.py` then declares `class Trie(ABCTrie)` where `ABCTrie` is that
`Mapping` subclass. So the chain crosses three things at once: a `try/except
ImportError` import fallback, `collections.abc` (which has its own history here
— [[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]],
`done`), and subclassing an ABC through a shim.

That is a lead and not a diagnosis. **I did not instrument the compiler.**
Whoever takes it should bisect by feeding the intermediate files directly —
`_base.py` alone, then `py.py` alone — before theorising, since one of those
three probably hangs on its own and that costs two compiles to find out.

## Why prio 55 rather than corpus priority

A hang is not a compat item. CLAUDE.md's own ranking language is explicit that
*"compiler syntax, segfaults, etc, all prio"*, and a non-terminating compile is
worse than a segfault for an automated driver: a crash returns and a hang holds
a core forever. This one held one for **forty hours**, on the box whose core
contention is the binding constraint on the whole test matrix, and nothing
reported it — no timeout, no watchdog, no log line. The corpus value of
html5lib is a separate question and is not what ranks this.

## Related, not duplicate

[[feature-b-module-shims-for-the-html5lib-corpus]] covers the shims this file
reaches. This ticket is the hang, which would still be a defect if every shim
were complete.

## Gate

`timeout 60` on the command above returns 0, not 124, and the file compiles or
emits a real diagnostic. Add whichever intermediate file the bisect blames as a
regression test with a timeout, since a hang cannot be gated by an expected
output — the test has to be the bound.
