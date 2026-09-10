---
slug: bug-n-from-dot-import-x-as-y-does-not-bind-y
track: N
type: bug
prio: 55
status: done
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, imports, aliases]
blocked-by: []
summary: "ALREADY FIXED by 27618dddf (`from . import mod as ALIAS` bound nothing); verified 2026-09-10 against compiler `ca814b0aabcc` and CLOSED without a code change. All FOUR of this ticket's own rows pass verbatim, not a paraphrase of them. It also carried a `Not measured` section naming `import x.y as z` and `from mod import name as alias` and warning that closing without them is the normalise-dont-special-case shape -- BOTH pass too, plus `import x.y` plain. The ticket told its closer what to check and was right to; the arms were checked."
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

# Closed 2026-09-10, frankB — fixed elsewhere, verified, no code change

Fixed by **27618dddf**, `fix(N): from . import mod as ALIAS bound nothing`,
which landed after this was filed. Nobody closed it.

Re-run against `ca814b0aabcc`, using **this ticket's own four rows** rather than
a paraphrase of them — a package with `_fallback.probe()` returning 2:

| row | result |
| --- | --- |
| `from . import _fallback` then `_fallback.probe()` | 2 |
| `from . import _fallback as _b` then `_b.probe()` | **2** |
| same, wrapped in `try/except ImportError` | **2** |
| same without the alias, wrapped in `try/except` | 2 |

## The two arms this ticket said not to close without

Its own `Not measured` section named them and said one arm fixed is the shape
`normalise-dont-special-case` warns about. Checked:

| arm | result |
| --- | --- |
| `from .named import VALUE as V` | 9 |
| `from .named import probe as p` then `p()` | 11 |
| `import tkpkg.named as n` then `n.VALUE` | 9 |
| `import tkpkg.named` then `tkpkg.named.VALUE` | 9 |

All four. A ticket that names the arms its closer must check, and the failure
mode if they are skipped, is worth more than one that merely reports a symptom —
this one was right to insist, and closing it on the headline row alone would
have left three spellings unexamined.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ce223b675.
