---
slug: feature-n-a-call-cannot-unpack-a-sequence-into-its-arguments
track: N
prio: 70
type: feature
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "`f(*seq)` is `error: expected expression`. 59 call sites in lekkerzeilen's entry-point closure, 35 of them the mixed `f(a, *seq)` form and one `f(**mapping)`; 38 of the 59 are in app.py alone. This is the wall the demo now stands at (app.py:626) after five earlier walls were cleared, and it is NOT patchable in the corpus the way the earlier ones were -- at 59 idiomatic sites the feature is cheaper than the edits."
---

# A call cannot unpack a sequence into its arguments

```python
v = Vec3(*angular)                      # error: expected expression
spawn = self.world.pound_at(*self.start[:2])
pound = self.world.pound_at(*self.start[:2], forced=self.level_forced)
f = Furniture(**dict(zip(columns, row)))
```

Measured at `120eeb39f`, binary `7cf02ff177ca`. The diagnostic is
`pascal26:<n>: error: expected expression`, pointing at the `*`.

## Population — counted with `ast`, not with a grep

| shape | sites |
| --- | --- |
| `f(*seq)` total | **59** |
| ...of which `f(a, *seq)` (fixed args before the star) | 35 |
| `f(**mapping)` | 1 |

Per file: `app.py` 38, `world.py` 5, `lines.py` 4, `__main__.py` 2, `atlas.py` 2,
`gfx.py` 2, `platform/_gl.py` 2, `rd.py` 1, `sim.py` 1, `ui.py` 1, `vessel.py` 1.

**The first count I took was 22 and it was wrong**, which is worth recording
because the error is the ordinary one: a `grep -E '\w\(\*[a-z_]'` matches
`COUNT(*)` inside an SQL string literal, misses `Furniture(**dict(...))`, and its
`[^)*]+` guard for the mixed form matches multiplication. Parsing each module and
walking for `ast.Starred` inside `ast.Call` cannot confuse a string for a call
and is three lines. Count this class with a parser.

## Why this one is not a corpus edit

The five walls cleared ahead of it were each one or three sites, and each edit
left the Python plainly better or equal (a `dict.get` cache that stopped
overloading one name with two types, a seam that stopped leaking ctypes). At 59
sites there is no version of that argument. `f(*seq)` is also not a corner of the
language — it is how you forward an argument list, splat a coordinate pair, or
build a record from a database row, which is exactly what these sites do:

    self.grids[row[0]] = Grid(*row[1:])        # world.py, a row from sqlite
    return from_wgs84(*from_utm(e, n, zone))   # rd.py, a coordinate pair

## Shape of the work

For a callee whose arity the compiler knows — which covers the constructors and
module functions that make up most of these sites — `f(a, *seq)` lowers to
`f(a, seq[0], ... seq[N-k-1])` for declared arity N and k fixed arguments, with a
length check on `seq`. That needs no new runtime concept and no dispatch change.

The cases that do need more thought, and should be scoped separately rather than
bundled: a callee reached by runtime dispatch (no declared arity to expand
against — and note `MAX_DYN_ARGS = 4` already caps that path, see
[[feature-n-a-runtime-dispatched-method-call-is-capped-at-four-arguments]]), a
star over something that is not a list/tuple, and `**mapping`, which is one site
here and wants keyword binding rather than positional expansion.

**Do not rank this on the 59.** Per CLAUDE.md's first-failure rule, it is the
first error in each file that names it, so what sits behind it in `app.py` is
unmeasured — and 38 of the 59 being in one file is the same histogram shape the
handbook warns reads as a big population when it is one file's contents.
