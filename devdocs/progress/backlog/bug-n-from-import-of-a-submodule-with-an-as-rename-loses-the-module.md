---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`from M import sub as alias` then `alias.f()` is a compile error — `undefined variable (f)` — while the SAME import without the rename works, and renaming a FUNCTION on from-import works. So it is specifically an `as` rename applied to a module-valued name. Plain modules and mimic_ shims behave identically, so this is not the shim mapping. It is the exact spelling html5lib/filters/sanitizer.py uses (`from six.moves import urllib_parse as urlparse`), which blocks the tractable half of the six.moves work."
---

# `from M import <submodule> as alias` loses the module

- **Type:** bug — **Track N** (Nil-Python frontend, import binding).
- **Found:** 2026-08-18 by frank3-fc, scoping the `urllib_parse` half of
  [[feature-b-mimic-six-moves-needs-http-client-and-urllib]].
- **Measured against:** `pinned` **v349** (`596799fd9c6e`, pin commit `a6e8e763e`).
- CPython accepts and runs every line below.

## Repro

`pp.py` (any module exporting a function), and `sm.py` re-exporting it under a
name:

```python
# sm.py
import pp as urllib_parse
```

```python
from sm import urllib_parse            # works
print(urllib_parse.urlparse("x"))      # works

from sm import urllib_parse as up      # compiles
print(up.urlparse("x"))                # error: undefined variable (urlparse)
```

## The boundary

| shape | result |
| --- | --- |
| `from M import sub` then `sub.f()` | ✅ |
| **`from M import sub as alias` then `alias.f()`** | **error: undefined variable (f)** |
| `from M import func as alias` then `alias()` (a FUNCTION, not a module) | ✅ |
| same two rows with `M` a plain module | identical — ✅ / ❌ |
| same two rows with `M` a `mimic_` shim | identical — ✅ / ❌ |
| `import M as alias` at top level then `alias.f()` | ✅ |

So the discriminator is narrow and it is not the shim mapping (which is
[[bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes]], a
different fault): it is an `as` rename applied to a **module-valued** name in a
from-import. Renaming a function is fine; not renaming is fine; aliasing a
module with a top-level `import ... as` is fine.

Reading, not a measurement: the rename appears to bind the name without
carrying whatever makes a module-valued binding resolvable, so the later
attribute lookup finds nothing.

## What it blocks

`html5lib/filters/sanitizer.py:15` is exactly this:

```python
from six.moves import urllib_parse as urlparse
...
uri = urlparse.urlparse(val_unescaped)
```

That is the ONE file the tractable half of the `six.moves` work was supposed to
unblock — `urllib.parse` is pure string manipulation against RFC 3986 and is
writable exactly. With this bug open, writing it unblocks **zero** files, so
the work is parked rather than done. See that ticket for the measurement.

**Do not close this by reshaping our shims.** The failing spelling is in the
corpus, and the shim side has no say in it: the same failure occurs between two
plain modules with no shim involved.
