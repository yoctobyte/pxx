---
track: B
prio: 62
type: feature
owner: unassigned
blocked-by: []
summary: "DECIDED 2026-08-19: ship xml.etree.ElementTree as a TREE MODEL only (Element, Comment, ElementTree + 10 members), no XML reader. ~60 lines plus a differential; unblocks the last 4 shim-blocked corpus files. The Comment-factory-is-its-own-tag identity must be exact or html5lib silently stops recognising comments."
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
