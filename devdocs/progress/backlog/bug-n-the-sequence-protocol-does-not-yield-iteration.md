---
track: N
prio: 48
type: bug
owner: unassigned
blocked-by: []
summary: "A class with `__len__` + `__getitem__` and no `__iter__` is iterable in CPython. In NilPy `for x in obj` is a compile error whose diagnostic names an unrelated internal (`pylib (count) not loaded`), and `list(obj)` compiles and returns an EMPTY list — a silent wrong answer, which is the worse half."
---

# The sequence protocol does not yield iteration

- **Type:** bug — Track N (Nil-Python frontend)
- **Opened:** 2026-08-19
- **Filed by:** Track B, writing `lib/rtl/mimic_xml_etree_elementtree.py`
  ([[feature-b-mimic-xml-etree-elementtree-tree-model]]). Not Track B's file, so
  it is handed over. CPython runs the repro correctly, so by the
  upward-compatibility rule in CLAUDE.md this is an N defect.
- **Measured on:** pinned `stable_linux_amd64/default/pinned` (v352), 2026-08-19.

## The repro

```python
class Seq:
    def __init__(self):
        self._items = ["a", "b", "c"]

    def __len__(self):
        return len(self._items)

    def __getitem__(self, i):
        return self._items[i]


s = Seq()
print(len(s), s[0], s[-1])   # 3 a c        -- correct in both
for x in s:                  # CPython: a b c
    print("iter", x)
print("list", list(s))       # CPython: ['a', 'b', 'c']
```

CPython falls back to the old sequence protocol: with no `__iter__`, it calls
`__getitem__` with 0, 1, 2, … until IndexError. This is not a legacy curiosity —
it is how a great deal of real code, including CPython's own pure-Python
`xml.etree.ElementTree.Element`, becomes iterable.

## Two symptoms, and the quiet one is the problem

| shape | pxx |
| --- | --- |
| `len(s)`, `s[0]`, `s[-1]` | correct |
| `for x in s:` | **compile error:** `pascal26:14: error: Nil Python: pylib (count) not loaded` |
| `list(s)` | **compiles, prints `[]`** |

The compile error is survivable — loud, early, at the right line — though its
text names an internal (`pylib (count)`) that has nothing to do with the source,
so it sends the reader looking in the wrong place. Worth fixing on its own even
if the fallback is not implemented.

`list(s)` is the real defect: it compiles clean and answers an empty list for a
three-element sequence. Nothing raises, and every downstream `len()`, sum, or
join reads as "there was nothing there". That is the plausible-wrong-value shape
from `devdocs/dev/root-cause-over-microfix.md`. **Even if the protocol fallback
is judged out of scope, `list()` over an object it cannot iterate must fail
rather than return `[]`.**

## The double case to check before closing

`devdocs/dev/normalise-dont-special-case.md`: iteration is reachable through at
least `for`, `list()`, `tuple()`, unpacking, `in`, and the comprehension forms.
`for` errors and `list()` silently empties, which is already two different
answers to one question — so grep the sibling arms rather than fixing the two
observed here.

## Not blocking

`lib/rtl/mimic_xml_etree_elementtree.py` defines `__iter__` explicitly (returning
`iter(self._children)`). That is **not** registered as a workaround: CPython's C
`Element` carries `tp_iter` too, so the behaviour is identical either way and the
spelling is a fair one to keep after this is fixed. The comment at that method
points here.

## Gate

Track N: the repro's `for` loop and `list()` both give `a b c` /
`['a', 'b', 'c']`, `make test-nilpy` green, self-host byte-identical. The
regression test must assert the **contents** of `list(s)`, not just that it
compiles — a test checking only compilation passed the entire time the answer was
`[]`.
