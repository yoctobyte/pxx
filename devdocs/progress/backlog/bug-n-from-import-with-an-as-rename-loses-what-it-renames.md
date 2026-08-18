---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`from M import X as alias` loses what X is. A renamed MODULE gives `undefined variable (f)` on any attribute; a renamed FUNCTION loses its signature — a zero-arg call SEGFAULTS and an omitted default is dropped, while a call with every argument explicit works. Not the shim mapping (two plain modules reproduce it) and not the rename in general (a plain `alias = f` assignment after the import is fine). Blocks sanitizer.py, the one file the tractable half of the six.moves work was meant to unblock."
---

# `from M import X as alias` loses what X is

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

### Renamed MODULES

| shape | result |
| --- | --- |
| `from M import sub` then `sub.f()` | ✅ |
| **`from M import sub as alias` then `alias.f()`** | **error: undefined variable (f)** |
| `import M as alias` at top level then `alias.f()` | ✅ |
| both rows with `M` a plain module | identical |
| both rows with `M` a `mimic_` shim | identical |

### Renamed FUNCTIONS — worse, and originally mis-scoped here

This ticket first said renaming a function was fine. **It is not**, and the
correction came from the coordinator running the zero-argument case; the
original row was measured with a one-argument function, which happens to be the
shape that works. Re-measured, one variable at a time:

| shape | result |
| --- | --- |
| `from M import f as alias` then `alias()` — **no parameters** | **SEGFAULT** |
| `from M import f as alias` then `alias(x)` — every argument explicit | ✅ |
| `from M import f as alias` then `alias(1)` where `f(a, lo=7)` — default omitted | **silently wrong** (empty, not 7) |
| `from M import f as alias` then `alias(1, 7)` — default supplied | ✅ |
| `from M import f` then `f()` — no rename | ✅ |
| `from M import f` then `alias = f` then `alias()` — assignment, not rename | ✅ |
| same-file `alias = f` then `alias()` | ✅ |

So a renamed function loses its **signature**, not its identity: calls that
supply every argument work, and calls that rely on the frame the callee expects
(zero arguments, or an omitted default) get a wrong frame — crashing when the
garbage is dereferenced and answering silently wrong when it is not. And it
needs the rename to be part of the **from-import**: a plain `alias = f`
assignment after the same import is correct.

Both readings above are readings of the tables; nothing here inspected the
lowering.

### Open question, deliberately not settled here

The function half may be an instance of the BLOCKED p88 (a call through a
procedural value core-dumps) rather than a separate fault — the rename
plausibly makes `alias` a procedural value. It may equally be the same fault as
[[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]], since
"loses the signature" describes both. **Do not fold them on resemblance.**
Whoever takes this should measure which, and the fact that a plain assignment
alias is CORRECT while a from-import rename is not is the discriminator to
start from.

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

---

## Coordinator measurement 2026-08-18 — the discriminator is the SOURCE NAME'S LENGTH

**This supersedes the argument-count reading above.** Both earlier tables were accurate
and both were confounded: every row that "worked" happened to use a **one-character**
function name (`f`, `z`), and every row that crashed used a longer one (`func`, `alias`,
`urlparse`). Argument count was correlated, not causal.

Measured on pinned v349, one variable at a time, module containing a single no-argument
`def`:

```
from mod import a    as al ; al()   ->  7            len 1  ok
from mod import ab   as al ; al()   ->  CORE DUMPED  len 2
from mod import abc  as al ; al()   ->  CORE DUMPED  len 3
from mod import abcd as al ; al()   ->  CORE DUMPED  len 4
```

Name sweep, same shape: `f` `g` `z` all return 7; `func` `helper` `run` `parse` `encode`
`lookup` all core-dump.

**The ALIAS's length is irrelevant** — only the source name matters:

```
from mod import a as b    ->  7
from mod import a as bb   ->  7
from mod import a as bbb  ->  7
```

So the rule is: **`from M import <name> as <alias>` crashes whenever `<name>` is two or
more characters.** Which is to say, for every realistic program. The one-character cases
are the only reason anyone measured a working row at all.

A length-1-vs-longer boundary points at the name being carried somewhere that holds a
single character, or a comparison reading only the first byte, rather than at anything
about calls, signatures or defaults. **Start there, not at the call site.**

### What this does to the surrounding tickets

- The "renamed function loses its SIGNATURE" reading is not supported by these rows —
  `a()` with no arguments works and `ab()` with no arguments crashes, so signature is not
  the axis.
- The open question about whether the function half is really the blocked p88
  (procedural-value calls) or the p90 (cross-module defaults) is **answered: neither.**
  Both of those are about what a call knows; this is about a name being lost at the
  import. Do not fold it into either.
- The `alias = f` assignment row still stands as correct and is still the useful control,
  because it isolates the rename from the binding.

**Method note, since this is the third confound today:** two sessions independently
produced contradictory tables, both true, because each held the name fixed while varying
what it suspected. Varying the axis nobody had thought to vary — the identifier itself —
is what resolved it. See the standing habit: when a repro passes, vary the thing you held
fixed.
