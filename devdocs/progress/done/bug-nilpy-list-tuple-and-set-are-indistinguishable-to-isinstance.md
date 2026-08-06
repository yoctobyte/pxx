---
track: N
prio: 70
type: bug
status: done
owner: claude-AN
summary: "NilPy: list, tuple and set all answer True to isinstance(x, list) AND isinstance(x, tuple), and a set reports type(x).__name__ == 'list'. Libraries routinely accept several container kinds and branch on isinstance to tell them apart, so working CPython code takes the wrong arm silently."
---

# `list`, `tuple` and `set` are indistinguishable to `isinstance`

- **Type:** bug (silent wrong branch) — **Track N**
- **Found:** 2026-08-06. Pre-existing (identical on `pinned`).
- **Priority raised to 70 by the user**, 2026-08-06:
  > *"lot of libraries use that trick to distinguish lists from dicts etc and
  > accept both as function param. that we use a list type underneath in either
  > case is sortof irrelevant.. so, this typing issue deserves a high prio
  > ticket — need to tag original type so we can't confuse lists from tuples"*

## Measured — the whole `isinstance` surface

`isinstance(v, list/tuple/dict/str/int/float)` and `type(v).__name__`, for one
value of each kind. Only the wrong cells are marked; everything else agrees with
CPython.

| value | CPython | pxx |
| --- | --- | --- |
| `[1,2]` | `list`, name `list` | **`list` + `tuple`**, name `list` |
| `(1,2)` | `tuple`, name `tuple` | **`list` + `tuple`**, name `tuple` |
| `{1,2}` | neither, name `set` | **`list` + `tuple`**, name **`list`** |
| `{"a":1}` | `dict`, name `dict` | `dict`, name `dict` — OK |
| `"s"` | `str` | `str` — OK |
| `5` | `int` | `int` — OK |
| `2.5` | `float` | `float` — OK |
| `True` | `int`, name `bool` | `int`, name `bool` — OK |
| `None` | none, name `NoneType` | none, name `NoneType` — OK |

So `dict`, `str`, `int`, `float`, `bool` and `None` are all exact. The defect is
confined to the **three kinds backed by `TPyList`** — list, tuple and set — which
are mutually indistinguishable, and a set additionally misreports its own type
name.

## Why this is a real bug and not a lax-is-fine divergence

NilPy is upward compatible with CPython: accepting what CPython rejects is a
feature (see `devdocs/dev/nilpy-semantics-divergences.md` — a mutable tuple is
explicitly NOT a bug for that reason). This one fails the test, because
**programs CPython accepts and runs give different answers**:

```python
def describe(x):
    if isinstance(x, list):  return "list of %d" % len(x)
    if isinstance(x, tuple): return "tuple of %d" % len(x)
    return "scalar"
print(describe((1, 2)))      # CPython "tuple of 2"   pxx "list of 2"

def flatten(v):
    out = []
    for e in v:
        if isinstance(e, list): out.extend(e)
        else:                   out.append(e)
    return out
print(flatten([[1, 2], (3, 4), 5]))
# CPython [1, 2, (3, 4), 5]
# pxx     [1, 2, 3, 4, 5]        <- the tuple was flattened too
```

Nothing raises. `isinstance(x, list)` is the standard way a Python library
accepts several container kinds through one parameter and tells them apart
inside — which is exactly the case the user named, and it means the blast radius
is "any third-party-shaped code", not "code that abuses tuples".

## The fix: the tag already exists — wire `isinstance` to it

The user's direction was to *tag the original type*. **That tag is already
there**, and this turns out to be the cheapest of the options considered.

`TPyList` carries `FIsTuple: Boolean` (`compiler/builtin/pylib.pas:81`). It is
set at every tuple-producing site — the parenthesised literal, `dict.items()`,
`enumerate()`, `zip()`, `popitem()`, `most_common()`, tuple repeat and concat —
and it is propagated on copy (`Result.FIsTuple := FIsTuple`). `pytype_name_v`
already reads it, which is why `type((1,2)).__name__` correctly says `tuple`
while `isinstance` gets it wrong:

```pascal
{ pytype_name_v — already correct }
if TPyList(o).FIsTuple then Result := 'tuple' else Result := 'list';

{ PyParseIsinstance — the bug, compiler/pyparser.inc }
if (nm = 'list') or (nm = 'tuple') then ci := FindUClass('TPyList');
```

Both names map to one class and the test is `AN_IS_TEST`. So the two halves of
the runtime already disagree, and the fix is to make `isinstance` ask the same
question `type().__name__` does:

1. **`list` / `tuple`** — stop mapping both to `TPyList`. Test the class AND the
   flag, via a small pylib predicate (`pyis_list_v` / `pyis_tuple_v`) so the
   frontend does not reach into a field.
2. **`set`** — has **no** flag at all, which is why `type({1,2}).__name__`
   answers `list`. With three kinds sharing one row, the natural move is to
   replace `FIsTuple: Boolean` with a small **kind** field (list / tuple / set)
   and update the ~15 assignment sites above. `pytype_name_v` then answers `set`
   correctly for free — a second bug fixed by the same change.

### Why not a distinct class

The user also suggested `type TPyTuple = type TPyList` — "change a definition
left and right, and code stays identical". The instinct (tag the type) is right
and is what the flag does; the specific mechanism does not fit here, and it is
worth writing down why so nobody re-proposes it:

- Pascal has no distinct-type alias for a **class**; the equivalent is an empty
  descendant, `TPyTuple = class(TPyList)`.
- A descendant is *inheritance*, and `AN_IS_TEST` is inheritance-aware, so
  `tuple is TPyList` stays **True** — it fixes `isinstance(list_val, tuple)` and
  leaves `isinstance(tuple_val, list)` broken. Only half the bug.
- Making them true siblings under a shared base fixes both, but every signature
  and cast naming `TPyList` across pylib would have to change — the opposite of
  "code stays identical".
- The flag needs none of that: one field, already present, already maintained at
  every construction site, and every function taking a `TPyList` keeps working
  unchanged.

Deliberately **not** in scope: enforcing tuple immutability. Rejecting
`t[0] = 9` rejects nothing a working CPython program does and costs a check on
every store — that divergence is chosen, and recorded as such.

## Relationship to the set decision

[[decide-nilpy-set-as-a-distinct-type-or-a-list]] (Track U) is the same root
cause seen from the set side, and already lists three consequences of the shared
row: `list - list` not being rejectable, a set printing as `[1, 3]`, and set
difference needing the alias to keep working. **This is its fourth**, and it is
the one that hits ordinary library-shaped code.

The user's "tag the original type" is direction for the typing half and is close
to that ticket's **option A** in its cheaper form (a flag rather than a whole
`TPySet` row). It does not by itself settle the set's `repr` or whether
`[1] - [2]` should raise — those stay with that decision, and a kind tag is what
makes both implementable.

## Gate

Per-fix loop. A `.npy` test asserting the full table above — `isinstance` against
`list`/`tuple`/`dict`/`str`/`int`/`float` and `type(x).__name__`, for a list, a
tuple, a set, a dict, a str, an int, a float, a bool and None — plus the
`describe` and `flatten` idioms, diffed against CPython with `tools/pydiff.py`.
Every currently-correct read path must stay green.


## Log

- 2026-08-06 — **resolved**, as scoped: the tag, not a class.

  `TPyList.FIsTuple: Boolean` became **`FKind: Integer`** with `PYSEQ_LIST=0` /
  `PYSEQ_TUPLE=1` / `PYSEQ_SET=2` (`compiler/builtin/pylib.pas`; mirrored in
  `defs.inc` beside the `VT_` tags, which the frontend needs and already does
  for those). LIST is 0 so a freshly-created `TPyList` is a list without anyone
  saying so. All 31 `FIsTuple` sites moved over mechanically — the assignments,
  and the propagations (`Result.FKind := FKind`, tuple repeat, concat), which
  now carry set-ness for free.

  - **`isinstance`**: new `pyseq_kind_v(v)` returns the kind (or -1 for a
    non-`TPyList`), and `PyParseIsinstance` answers `list`/`tuple`/`set` from it
    instead of mapping two names onto one class.
  - **`set` was never stamped at all** — hence `type({1,2}).__name__ == 'list'`.
    Three sites now do it: the `{...}` display (`PyParseListLiteralT`, whose
    comment used to read *"Set-literal braces stay lists"*), the `set(xs)`
    constructor (`pyset_of`), and the empty `set()` (`PyParseEmptySet`, via a
    new `pylist_mark_set`).
  - **repr follows the kind**: `{1, 2}` for a set, and `set()` for the empty one,
    since CPython has no empty-set display. That closes consequence 3 of
    [[decide-nilpy-set-as-a-distinct-type-or-a-list]] as a side effect.

  Verified: `test/test_nilpy_container_kind_tag.npy` (new, in `make test-nilpy`)
  — the full `isinstance` × type-name surface for all nine value kinds, the
  `describe`/`flatten` narrowing idioms, kind survival through `+`, `*`,
  `list()`, `sorted()` and a comprehension, runtime-produced tuples
  (`dict.items()`, `zip()`), both `set` constructors, and repr. All lines match
  CPython. `tools/gate.sh quick` GREEN; the probe corpus shows no regressions
  and `isinstance` probes that previously failed now pass.

### One divergence this made VISIBLE (pre-existing, not introduced)

A set now prints with braces, so its ORDER is on show: `{3, 1, 2}` where CPython
prints `{1, 2, 3}`. pxx preserves insertion order; CPython's set order follows
hashing. Before this change the same set printed `[3, 1, 2]` — wrong brackets
*and* the same order — so this is strictly closer, not a new defect.

Matching CPython's order needs real hash-set semantics, which is exactly
[[decide-nilpy-set-as-a-distinct-type-or-a-list]]'s option A and stays with that
decision. Noted here so the next person to see `{3, 1, 2}` knows it is known and
where it belongs.
