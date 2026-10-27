---
track: N
prio: 70
type: bug
---

# Keywords on a dynamic receiver bind by the first candidate's parameter order

Found building songformatter (2026-10-27, peer session): the live preview was
BLACK. render() takes `c = backend if backend is not None else
canvas.Canvas(...)` and calls `c.rect(2, 2, w, h, stroke=1, fill=0)`. The
reportlab shim declares rect(x, y, w, h, stroke, fill) and the app's own backend
declares rect(x, y, w, h, fill, stroke). pxx printed `fill= 1 stroke= 0` where
CPython prints `fill= 0 stroke= 1`, so the page border was filled solid black.

**Cause.** PyParseVariantMethod binds the keywords ONCE, against the static pick
(the first candidate found), and every runtime arm reused that positional chain.
The source comment said this "is right as long as the candidates agree on
parameter order", which nothing guaranteed. It depended on which class the scan
met first, which is why B in the same file looked fine.

**Fix.** The call is recorded as written (positionals, then keyword name and
expression pairs) before the bind. When the call has keywords, each runtime arm
rebuilds its chain against its OWN parameter names and fills its own defaults.
An arm that lacks a written keyword, or a required parameter nobody wrote, is
dropped, the same as an arm that cannot be completed. Calls with a star, a
`**` spread or a collecting callee keep the shared chain.

Test: test/test_nilpy_keywords_bind_per_runtime_arm.npy (two user classes,
CPython oracle). Pin v452 prints the C rows wrong.
