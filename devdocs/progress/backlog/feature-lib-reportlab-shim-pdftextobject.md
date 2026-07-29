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

## Gate

Both files compile with `$(PXX_STABLE)`; `make lib-test` green.
