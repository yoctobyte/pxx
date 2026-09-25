---
type: bug
track: N
prio: 40
status: open
slug: bug-n-an-n-way-zip-leaks-its-streams-and-their-cursors
summary: zip() over five or more iterables (pyiter_zip_n, reached through PyZipTailList) leaves every stream, its cursor and the temporary list of streams alive after the zip is drained. The two-way zip is clean. map(f, a, b, ...) is built on the same cursor and inherits the leak.
---

# An N-way zip leaks its streams and cursors

Measured 2026-09-25 (frankH), `-dPXX_ALLOC_CENSUS`, 3000 iterations:

- `len(list(zip(a, b, c, d, e)))` on pin v428: allocs 115763, frees 37609,
  live 78154 (about 26 per call).
- `len(list(zip(a, b)))` on pin v428: live 23.

`-dPXX_OBJTRACE` on ONE call inside a def: 11 objects never freed. Those are
the five argument lists (each ends at r1), the zipn temp list, and five
cursor/box pairs.

Tried and measured as NO CHANGE: dropping the explicit PXXObjRetain on each
cursor in pyiter_zip_n (its FSrc.append also retains). The live count did not
move, so that retain is not the whole story. Trace every object that
survives before fixing.

Inherited by `map(f, a, b, ...)` (pyiter_map_star = MAP over zip_n):
`len(list(map(h, a, b)))` shows 59018 live over 3000 iterations.
