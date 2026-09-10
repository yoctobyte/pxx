---
slug: bug-n-from-dot-import-x-as-y-does-not-bind-y
track: N
type: bug
prio: 55
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, imports, aliases]
blocked-by: []
summary: "`from . import _fallback as _b` compiles and then `_b` is `undefined variable`; `from . import _fallback` (no alias) works and runs. The alias on a RELATIVE import of a submodule binds nothing, with no diagnostic at the import itself -- the error surfaces later at the use site, which is what makes it read as a scoping bug rather than an import one. Found by probing the guarded-import shape from lekkerzeilen's portability seam; it is NOT that seam's wall (that is bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved) and is filed on its own because a probe turned it up, not a program."
---

# Measured 2026-09-10, compiler `c3e38195d910`

Four shapes, one variable between them:

| shape | result |
| --- | --- |
| `from . import _fallback` then `_fallback.probe()` | **compiles, prints 2** |
| `from . import _fallback as _b` then `_b.probe()` | `pascal26:2: undefined variable (_b)` |
| same, wrapped in `try/except ImportError` | `undefined variable (_b)` |
| same without the alias, wrapped in `try/except` | **compiles, prints 2** |

So the `try/except` is irrelevant and the **alias is the whole variable.** That
is worth recording because the shape it was found in looked like a guarded-import
bug and is not one — a probe that varied only the alias is what separated them.

# Why the diagnostic makes it worse than it looks

The import statement itself is accepted silently. The failure appears at the
first USE of the alias, as `undefined variable`, which points a reader at scoping
or at a typo rather than at the import two lines above. A refusal at the import
would cost the reader nothing and save the chase.

# Not measured

Whether `import x.y as z` and `from mod import name as alias` share the cause.
Whoever takes this should check both before closing — one arm fixed is the shape
`normalise-dont-special-case` warns about.
