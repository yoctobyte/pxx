---
track: N
prio: 72
type: bug
blocked-by: []
summary: "A class with __getitem__/__len__ now iterates with `for`, but every OTHER consumer of iteration still refuses it — and `list(b)` returns [] SILENTLY. Found while fixing feature-nilpy-for-loop-getitem-protocol-fallback; the for-loop was one path of several serving one concept."
---

# The old-style iteration protocol reaches only the `for` loop

Filed 2026-08-19 from [[feature-nilpy-for-loop-getitem-protocol-fallback]], which
fixed the `for` lowering. The repo's own rule says to grep for the sibling arms
before closing a double case, so this is those siblings.

All rows measured at HEAD **and on pinned** — every one is pre-existing, none is
a regression from the for-loop fix.

```python
class Box:
    def __init__(self, items): self.items = items
    def __getitem__(self, idx): return self.items[idx]
    def __len__(self): return len(self.items)
b = Box([1, 2, 3])
```

| shape | CPython | pxx |
| --- | --- | --- |
| `for x in b` | 1 2 3 | **fixed** — 1 2 3 |
| `[x*2 for x in b]` | `[2, 4, 6]` | **fixed** — shares the lowering |
| `list(b)` | `[1, 2, 3]` | **`[]` — SILENT WRONG VALUE** |
| `sum(b)` | `6` | `TypeError: expected a str, a list or a dict, got object` |
| `2 in b` | `True` | `TypeError: argument is not a container (no __contains__)` |
| `p, q, r = b` | `1 2 3` | compile error |

## The one that matters most

**`list(b)` answers `[]`.** Not an error — an empty list, which flows onward and
produces a wrong result far from its cause. That is this repo's expensive
failure shape, and it is the reason this is filed as a `bug` rather than a
feature request. The other rows fail loudly and are merely missing.

## Shape of the fix

One concept — "this object is iterable by index" — is served by several
independent paths: the `for` lowering (now fixed), `list()`/`sum()`'s container
conversion, the `in` operator's `__contains__` check, and tuple unpacking. Each
tests for a container in its own way, which is why fixing one moved none of the
others.

The right fix is almost certainly NOT four more special cases but one shared
"materialise this receiver as a sequence" helper the four consumers call —
`normalise-dont-special-case`. `pyiter_of_userobj` already exists for the
`__iter__` protocol and is the natural place for the `__getitem__` fallback to
live, so that every consumer that already goes through a cursor gets it at once.

## Also still missing: `__getitem__` WITHOUT `__len__`

CPython walks 0.. and stops on `IndexError`, so a class with only
`__getitem__` is iterable. pxx requires both and now says so explicitly rather
than dying with "pylib (count) not loaded". Loud and honest, but still a gap.
