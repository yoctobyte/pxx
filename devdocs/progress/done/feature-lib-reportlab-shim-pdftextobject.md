---
track: B
prio: 45
type: feature
---

# reportlab shim: `PDFTextObject.setTextOrigin` (and whatever follows it)

```
pascal26:1198: error: Nil Python: PDFTextObject has no method setTextOrigin
```

This is now the wall for songformatter's `convertrawtext.py` and
`SongFormatter.py` — the two modules that do PDF rendering. Everything before it
compiles: with the container methods landed
([[feature-nilpy-container-method-gaps]]), both files get from line 334 to line
1198.

A LIBRARY gap, not a compiler one — hence Track B. The shim exists and is
missing methods; `setTextOrigin` is the first, and the rest of the text-object
surface the file uses should be censused in one pass rather than discovered one
error at a time (grep the two files for `.set`/`.text`/`.draw` calls on the
object returned by `beginText`).

The rest of songformatter — `key_analysis`, `render_backend`, `settings` —
already compiles, and `kadrv.py` matches CPython exactly.

## Resolved 2026-07-30

Censused the text-object surface both files use rather than adding one method
per error: `setFont`, `setTextOrigin`, `textLine`, `textOut` — three existed, so
only `setTextOrigin` was missing (plus `moveCursor` / `getX` / `getY`, which
reportlab pairs with it and which cost nothing).

reportlab's `setTextOrigin` resets the LINE START as well as the cursor, so the
next `textLine()` returns to that x rather than to the origin `beginText()` was
given — songformatter opens a text object at one margin and then moves it.

Five more walls stood behind it, none of them reportlab: `TPyList.read`,
transitive capture for LAMBDAS, class attributes beside an `__init__`, a keyword
argument being read as a module assignment, and `nametowidget` losing the tab's
class. All fixed; `SongFormatter.py` compiles and runs to the preview render.

## Gate

Both files compile with `$(PXX_STABLE)`; `make lib-test` green.

## Log
- 2026-07-30 — resolved, commit HEAD.
