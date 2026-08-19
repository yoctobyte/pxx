---
track: B
prio: 62
type: feature
owner: frankonpiler-etree
blocked-by: []
summary: "DECIDED 2026-08-19: ship xml.etree.ElementTree as a TREE MODEL only (Element, Comment, ElementTree + 10 members), no XML reader. ~60 lines plus a differential; unblocks the last 4 shim-blocked corpus files. The Comment-factory-is-its-own-tag identity must be exact or html5lib silently stops recognising comments."
status: done
---

# `mimic_xml_etree_elementtree`: the tree model

**Implements [[decide-xml-etree-thin-tree-model-or-a-real-xml-library]]** (user,
2026-08-19: *"for now the minimal shim; if we want to extend it we can write the XML
importer later"*). Filed as work because a decided ticket that is never re-filed is
invisible to `ready`/`next`.

## Scope — measured against pinned v352, not assumed

Factories: `Element` (5 uses), `Comment` (3), `ElementTree` (1).

Members: `.tag .text .tail .attrib .get .set .append .insert .remove .find`, plus
`len(elem)`, `elem[i]`, and iteration.

**Out of scope:** `parse`, `fromstring`, `iterparse`, `SubElement`, `findall`, `itertext`,
namespaces beyond plain string tags, and serialisation — html5lib defines its own
`tostring` at `treebuilders/etree.py:262`. There is no XML text on either side of this
interface; html5lib parses the HTML itself and only wants somewhere to hang a tree.

## The one identity that must be exact

`Comment("x").tag` **IS the `Comment` function**. CPython uses the factory as its own
sentinel tag and html5lib depends on it:

```python
ElementTreeCommentType = ElementTree.Comment("asd").tag
...
if node.tag == ElementTreeCommentType:
```

Get this wrong and comments are silently not recognised — no error, just wrong output.
Worth a dedicated assertion rather than trusting it falls out.

## Missing entry points: MEASURE, do not assume

The user was asked whether a shim should omit a missing entry point (compile error) or
include-and-refuse (runtime error) and deliberately did not settle it, so **do not invent
a general rule.** Decide this one by measurement: grep the corpus for references to
`parse`/`fromstring`/`iterparse` that are imported but never called. **Nothing speculative
→ omit them** (loud and early). **Something → include and refuse**, naming the decision.

## Gate

Track B: build with `$(PXX_STABLE)` — never rebuild the compiler. `make lib-test` green,
plus a differential against CPython on the tree operations. Follow `mimic_codecs.pas` /
the existing `mimic_*` pattern rather than inventing a second shape. A compiler or
frontend gap found while writing it goes to the owning lane as a ticket, not a workaround.

**Report past-a-wall separately from onto-the-next-wall** — this unblocks 4 files, which
is not the same as 4 files compiling.

---

## Resolved 2026-08-19 — what landed

`lib/rtl/mimic_xml_etree_elementtree.py` (~200 lines with the docstrings) and
`test/lib_mimic_xml_etree_elementtree.npy` (56 assertions), wired into
`make lib-test`. Built and measured against pinned **v352**
(`stable_linux_amd64/default/pinned`, sha `0d2087d629bf`).

The test is a true differential: it runs unmodified under CPython, and the two
outputs are **byte-identical** (`diff` clean, 56 `=ok`, `MIMIC-XML-ETREE OK`).

### Missing entry points: MEASURED, and the answer is OMIT

Grepped html5lib, reportlab, tinycss2 and webencodings for `parse` /
`fromstring` / `iterparse` on this module. Outside `tests/`, the only importer is
`html5lib/_utils.py:13` (`import xml.etree.ElementTree as default_etree`), which
never reaches for any of them; reportlab's single hit is a *comment* about a
future release (`platypus/paragraph.py:1825`). `treebuilders/etree_lxml.py:365`
does call `fromstring`, but on `lxml.etree`, a different module with no shim.

**Nothing imports them without calling them, so they are omitted** and a caller
gets an unresolved-name error at its own call site. The general
omit-vs-present-and-refusing rule stays unfiled, as the user left it.

### What the differential caught that reading would not have

`find("*")` matches **any** child, comments included — CPython's `find("*")` on a
div whose first child is a comment returns the comment, and `findall("*")` lists
its tag as the `Comment` function. This shim shipped the plausible reading ("any
element", skip comments) and the diff against CPython failed on it.

Also caught by running it rather than reasoning: `path.split("/")` shreds the one
qualified tag html5lib asks for,
`{http://www.w3.org/1999/xhtml}html`, whose URI carries three slashes. It
answered `None` — for the right path. `_split_steps` is brace-aware for the same
reason upstream's tokenizer is.

### The Comment identity: exact, and its neighbour is NOT

`Comment("x").tag` is the `Comment` function, and the identity html5lib depends
on holds: two comments' tags compare equal, an element's tag does not, and the
tag is not a string. Asserted directly (five checks), not left to fall out.

The neighbouring spelling `Comment("x").tag == Comment` answers **False** where
CPython answers True, because `g = f` boxes a NilPy function on the heap and
equality compares the box —
[[bug-n-a-function-stored-in-a-variable-is-not-equal-to-the-function]]. html5lib
never writes that form (both its comparands come from a call result, which keeps
the raw code pointer), so nothing is blocked. The test asserts the working
spellings and records the divergence in the ticket rather than baking a wrong
answer into an assertion.

### Three Track N bugs filed on the way, none blocking

- [[bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view]] —
  `keys`/`items`/`values` on a user class, through an untyped receiver, segfaults
  or answers a garbage 6-element list for a 2-key dict. Exactly those three
  names; `get`/`append`/`insert`/`remove`/`clear`/`find`/`set`/`extend`/`pop` are
  all fine, and a statically typed receiver is fine. The shim keeps `keys()` /
  `items()` (they are part of upstream's interface and work statically); the test
  walks attributes through `.attrib`, which is what html5lib does anyway.
- [[bug-n-a-function-stored-in-a-variable-is-not-equal-to-the-function]] — above.
- [[bug-n-the-sequence-protocol-does-not-yield-iteration]] — `__len__` +
  `__getitem__` with no `__iter__`: `for x in obj` is a compile error naming an
  unrelated internal, and `list(obj)` compiles and returns `[]`. The shim defines
  `__iter__` explicitly, which is exact rather than a workaround (CPython's C
  `Element` carries `tp_iter`).

All three are registered as coding-pattern landmines in
`devdocs/dev/track-b-workarounds.md`.

### PAST A WALL, NOT ONTO FOUR COMPILING FILES — and the next wall is already fixed

`tools/nilpy_ladder.py`, run twice against pin v352 (shim moved aside, then back):

| | before | after |
| --- | --- | --- |
| compile | 6/48 | **6/48 — unchanged** |
| `missing module: xml_etree_elementtree` | 4 | 0 |
| `Nil Python: unknown base class dict` | 0 | 4 |

The four are `_utils.py`, `treebuilders/__init__.py`, `treewalkers/__init__.py`
and `serializer.py` — only the first imports the module directly; the other three
reach it through `from .._utils import default_etree`, so the wall propagates
along imports. All four are now past it and onto `class X(dict)`.

`treebuilders/etree.py`, the file that actually *uses* the tree model, did NOT
move: it was already stopped earlier by `unknown base class list` (that count is
3 before and 3 after), so it has never yet reached the point of asking this shim
for anything. Worth stating plainly — "the file that needed ElementTree" is the
one a reader assumes moved.

**That next wall is already fixed at HEAD and is waiting on a pin, not on work.**
[[feature-nilpy-subclass-a-builtin-type]] resolved in `1cbe666b5` (2026-08-18
14:05); pin v352 is `0e5039b0178d` from 11:15 the same morning, and
`git merge-base --is-ancestor 1cbe666b5 0e5039b0178d` says no. Confirmed by
measurement, not inference: `class X(dict)` / `(list)` / `(str)` are all still
`unknown base class` on v352.

So the ladder should move on the next pin without anyone writing code — and this
row is worth re-running then, because "fixed at HEAD" and "unblocked for B" are
two different claims. Pins hold the repo-wide lock and belong to whoever holds
that slot, so this ticket does not run one.

### Gate

`make lib-test` green (Track B), built with `$(PXX_STABLE)`; the compiler was not
rebuilt. Plus the CPython differential above, which is the part that actually
constrains the shim.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
