---
type: bug
track: N
prio: 40
status: done
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

## Closed (2026-10-02, frankuser): fixed by f72168f983, never closed

f72168f983 ("a fresh object compared, or given to
isinstance/getattr/zip/map/literal_eval, is released") fixed this and added a
census row:
`test/test_nilpy_zip_map_literal_eval_and_eval_bytes_release_what_they_build.npy`,
assert_no_leak bound 300 with a `keep` control. Its comment gives pin v451 as
~24,900 live.

Re-measured at HEAD (800004e7be plus local work). A def ran a five-way
`zip` into `list`, a two-way `zip`, `map(h, a, b)`, `sum(map(h3, a, b, c))`,
a for-in over a five-way zip, and a comprehension over a three-way zip. After
1 pass and after 1001 passes the census reads live=5 both times, and the value
matches CPython (74074).

A module-level version of this program still leaked 11 objects per pass on
2026-10-02. That was not zip. A list was stored raw into a slot an earlier
`x = len(...)` had made an int:
bug-n-a-module-name-rebound-to-another-type-inside-a-block-stores-raw.
