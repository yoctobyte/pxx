---
track: U
prio: 62
type: decide
blocked-by: []
summary: "The last shim row on the corpus is xml.etree.ElementTree (4 files). MEASURED: html5lib uses it as a TREE MODEL, not as an XML library — 3 factories and 10 element members, no parse, no fromstring, no XPath, and html5lib writes its own tostring. So a ~60-line thin shim would serve every corpus caller. The fork is not effort, it is NAMING: may a module called xml.etree.ElementTree ship without the ability to parse XML? Recommendation: yes, thin, with the parser surface absent and loud."
---

# `xml.etree.ElementTree`: a thin tree model, or a real XML library?

- **Track U** — a decision for the user. Filed 2026-08-18 by frank3-fc from
  [[feature-b-the-module-shim-batch-blocking-the-python-corpus]], which fences
  this question off explicitly rather than letting a shim job settle it.
- **Measured against:** `pinned` **v352** (`0d2087d629bf`, pin `b14da0847`).

## Why this is the question now

After the 2026-08-18 shim batch, **the corpus has no thin-stdlib-shim work left
except this row.** The remaining missing-module rows on the ladder are:

| row | files | what it actually is |
| --- | --- | --- |
| `xml_etree_elementtree` | **4** | this question |
| `genshi_core` | 2 | a third-party package, not stdlib |
| `lxml` | 1 | a third-party package (a C library binding) |
| `weakref` | 1 | a runtime lifetime facility, not a shim |

So this row is the entire remaining shim lever, and it is blocked on a
naming/scope decision rather than on effort.

## What the corpus ACTUALLY uses — measured, not assumed

Every `ElementTree.<name>` reference in html5lib's library code:

```
5  ElementTree.Element
3  ElementTree.Comment
1  ElementTree.ElementTree
```

And every member touched on the elements it builds:

```
.tag  .text  .tail  .attrib  .get  .set  .append  .insert  .remove  .find
```

plus `len(elem)`, `elem[i]`, and iteration.

**What it does NOT use:** `parse`, `fromstring`, `iterparse`, `SubElement`,
`findall`, `itertext`, namespaces beyond plain string tags, or any
serialisation — `html5lib/treebuilders/etree.py:262` defines its **own**
`tostring`. There is no XML text on either side of this interface: html5lib
parses HTML itself and only wants somewhere to hang the resulting tree.

One quirk that must be reproduced exactly: `ElementTree.Comment("x").tag` **is
the `Comment` function itself** (CPython uses the factory as a sentinel tag),
and html5lib relies on that identity —
`ElementTreeCommentType = ElementTree.Comment("asd").tag`, then `node.tag ==
ElementTreeCommentType`.

## The fork

**It is not "how much work".** A tree model with those members is roughly 60
lines and is exactly the kind of closed, testable thing the other `mimic_*`
shims are. The question is what we are willing to put an upstream name on:

**Option A — thin tree model (recommended).** Ship `mimic_xml_etree_elementtree.py`
with `Element`, `Comment`, `ElementTree` and the ten members above. `parse`,
`fromstring` and `iterparse` are **absent**, so a caller reaching for them gets
a loud unresolved-name error naming this decision.
- *For:* unblocks 4 files now; matches every measured caller; consistent with
  `mimic_urllib_request` (present and refusing) and the T1 tier in
  `devdocs/dev/python-compat-tiers.md`.
- *Against:* a module named `xml.etree.ElementTree` that cannot read XML is a
  name promising more than it delivers. Someone will eventually `parse()` a
  file and meet the wall well after choosing the module.

**Option B — a real XML implementation.** Tokeniser, well-formedness, entity
and namespace handling, serialisation, and enough XPath for `find`/`findall`.
- *For:* the name then means what it says; pxx gains a genuine capability that
  apps (not just this corpus) would use.
- *Against:* it is a project, not a shim; nothing in the corpora needs it; and
  it would block these 4 files for as long as it takes.

**Option C — ship A under a non-upstream name** (e.g. `pxxtree`) and leave the
upstream name unclaimed.
- *Against:* it fails the mission test recorded in `python-compat-tiers.md` —
  the corpus source says `import xml.etree.ElementTree` and we do not get to
  edit it. This option unblocks nothing.

## Recommendation

**A**, with the absences explicit and loud, and a docstring that says the module
is a tree model rather than an XML implementation. If B is ever wanted it is a
separate, honestly-ranked project — the same call already made for `minidom` in
[[feature-b-a-real-minidom-is-an-implementation-not-a-shim]], and A does not
foreclose it.

If A is chosen, the work is ready to start immediately and is measured: ~60
lines plus a differential test against CPython's real `xml.etree.ElementTree`,
in the shape of the eight `mimic_*` shims already gated by `make lib-test`.
