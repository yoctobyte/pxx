---
track: N
prio: 55
type: bug
owner: frankonpiler-an
blocked-by: []
summary: "A user class's `keys()`/`items()`/`values()` called through an untyped (dynamic) receiver is dispatched as a DICT VIEW instead of the method: segfault, or a garbage list of empty strings and None when the result is consumed. Exactly three names; every other colliding name (`get`, `append`, `insert`, `remove`, `clear`, `find`, `set`, `extend`, `pop`) dispatches correctly."
status: working
---

# A user class's `keys()`/`items()`/`values()` is dispatched as a dict view

- **Type:** bug — Track N (Nil-Python frontend)
- **Opened:** 2026-08-19
- **Filed by:** Track B, writing `lib/rtl/mimic_xml_etree_elementtree.py`
  ([[feature-b-mimic-xml-etree-elementtree-tree-model]]). Not Track B's file, so
  it is handed over. CPython runs every shape below correctly, so by the
  upward-compatibility rule in CLAUDE.md this is an N defect, not a dialect
  choice.
- **Measured on:** pinned `stable_linux_amd64/default/pinned` (v352), 2026-08-19.

## The repro — 12 lines, no shim, no import

```python
class C:
    def __init__(self):
        self.n = 5

    def keys(self, a=None, b=None):
        return "USERMETHOD"


def f(o):
    print("keys", o.keys())


f(C())
```

CPython prints `keys USERMETHOD`. pxx compiles clean and **segfaults** (exit
139), printing nothing at all — not even the `keys ` prefix.

## The boundary — it is the NAME, and only three of them

Same class, same dynamic call site, one name changed. `mykeys` is the control:
an identically-bodied method with a non-colliding name.

| method name | through `def f(o): o.<name>()` |
| --- | --- |
| `mykeys` | `USERMETHOD` — correct |
| `keys` | **segfault** |
| `items` | **segfault** |
| `values` | **segfault** |
| `get` | `USERMETHOD` — correct |
| `append` | `USERMETHOD` — correct |
| `insert` | `USERMETHOD` — correct |
| `remove` | `USERMETHOD` — correct |
| `clear` | `USERMETHOD` — correct |
| `find` | `USERMETHOD` — correct |
| `set` | `USERMETHOD` — correct |
| `extend` | `USERMETHOD` — correct |
| `pop` | `USERMETHOD` — correct |

So it is not "builtin container method names shadow user methods" in general —
`append` and `get` collide just as hard and work. It is these three, which are
exactly the **dict view** methods, and the call looks as though it is being
lowered to a dict-view builtin against a receiver that is not a dict.

## The other half of the boundary: a STATIC receiver is fine

```python
c = C()
print(c.keys())          # -> USERMETHOD, correct
def f(o): print(o.keys())  # -> segfault
f(c)
```

Only the dynamically-typed receiver (an unannotated parameter) is affected, which
is why this survived: the spelling in a test is usually the static one.

## Why this is worse than a segfault — it can answer GARBAGE

A crash has a location. This does not always crash. Against the real shim, where
`keys()` returns `list(self.attrib.keys())` over a two-entry dict:

```python
def f(node):
    k = node.keys()
    print("k", k, len(k))       # k [, None, , , , ] 6      <-- want ['z', 'a'] 2
    print(sorted(k))            # TypeError: '<' not supported between
                                #   instances of 'NoneType' and '<unknown>'
```

A six-element list of empty strings and a `None`, for a dict with two keys. The
`len()` is wrong, the contents are wrong, and nothing raised until something
tried to order it — the plausible-wrong-value shape from
`devdocs/dev/root-cause-over-microfix.md`. A caller that only iterated the
result, or only took `len()`, would carry the wrong answer forward silently.

A third manifestation, from the same call in a longer expression, was
`TypeError: expected a number, got int` — so the observable symptom depends on
what consumes the result, which is another reason it reads as a lowering fault
rather than a dispatch miss.

## Suspected mechanism (a lead, not a diagnosis — MEASURE it)

`keys`/`items`/`values` are presumably special-cased in the NilPy lowering of a
method call so that `d.items()` on a dict maps to the container builtin. On a
receiver whose static type is unknown, that special case appears to fire anyway
and reinterpret the object as a dict. Per `devdocs/dev/debugging-playbook.md`,
print what the compiler inferred (`PXXDBG=n.locals`, `a.ir:f`) rather than
theorising — the three-names-and-no-others pattern is the fact; the mechanism
above is a guess.

Check the sibling arms before closing
(`devdocs/dev/normalise-dont-special-case.md`): if the fix is per-name, the next
dict/list/set view method added to the special case will land with the same hole.

## Not blocking

`lib/rtl/mimic_xml_etree_elementtree.py` keeps `keys()` and `items()` — they are
part of CPython's `Element` interface and they work through a statically typed
receiver, which is what `test/lib_mimic_xml_etree_elementtree.npy` asserts.
html5lib reaches attributes through `.attrib` rather than `Element.keys()`, so no
corpus file is blocked. Registered as a coding-pattern landmine in
`devdocs/dev/track-b-workarounds.md` instead.

## Gate

Track N: the repro above prints `keys USERMETHOD` (and the same for `items` /
`values`), `make test-nilpy` green, self-host byte-identical. Add the three-name
matrix as a `.npy` regression test — a single-name test would pass while the
other two stayed broken.
