---
track: B
prio: 55
type: feature
blocked-by: [bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero, bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]
summary: "The xml_dom ladder row (4 files) is two unrelated questions. Three files need only `Node` — 12 integer constants, zero methods, closed by the DOM spec, trivially shimmable. One file needs a real DOM (~25 methods plus a private minidom internal) and is a project, not a shim. MEASURED CONCLUSION: do not write it — the shim unblocks ZERO files today, and writing it before the trailing-class initialiser bug lands would produce a shim whose every constant reads as 0."
status: working
owner: frank3-fc
---

# `xml.dom` is two questions, and neither one is worth doing yet

- **Type:** feature (shim) — **Track B**. Measured 2026-08-17 by frank3.
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- **Recommendation: file and stop.** The code is not the deliverable here; the
  measurement is, and it says don't.

## The row, and what is actually behind it

`missing module: xml_dom` is row 3 of the corrected ladder table
(`tools/nilpy_ladder.py`), 4 files. **Only three of them import `xml.dom` at
all** — the fourth inherits the wall transitively:

| file | imports | needs |
| --- | --- | --- |
| `html5lib/treewalkers/base.py` | `from xml.dom import Node` | `Node` constants only |
| `html5lib/treewalkers/dom.py` | `from xml.dom import Node` | `Node` constants only |
| `html5lib/treewalkers/etree.py` | *nothing* — inherits via `from . import base` | — |
| `html5lib/treebuilders/dom.py` | `from xml.dom import minidom, Node` | **a real DOM** |

Worth noting for anyone reading a ladder row as a work estimate: **a row counts
transitive victims.** A grep of the corpus source finds three importers; the
table says four. Both are right, and only the table answers "how many files does
this unblock".

## Question 1 — `Node`: tiny, closed, and complete

Read off **CPython** rather than off the call sites (a table built from call
sites does not announce what it omitted):

```
>>> [x for x in dir(xml.dom.Node) if not x.startswith('_') and callable(...)]
[]
```

`xml.dom.Node` has **twelve integer constants and zero methods**. It is the DOM
spec's `nodeType` enumeration and nothing else, so a shim of it is not a
partial approximation — it is the *whole* class, fixed by a published spec, with
no version drift to track. About 20 lines.

The corpus uses it exactly as expected: `Node.DOCUMENT_NODE`, `Node.TEXT_NODE`,
`Node.ELEMENT_NODE`, `Node.COMMENT_NODE`, `Node.DOCUMENT_TYPE_NODE`,
`Node.ENTITY_NODE`, `Node.CDATA_SECTION_NODE`, `Node.DOCUMENT_FRAGMENT_NODE` —
8 of the 12, all as comparison operands.

## Question 2 — `minidom`: a project, not a shim

`treebuilders/dom.py` builds and mutates a document. The surface it touches:

```
appendChild attributes childNodes cloneNode createComment createDocumentFragment
createElement createElementNS createTextNode firstChild hasAttributes
hasChildNodes insertBefore namespaceURI nodeName nodeType nodeValue normalize
ownerDocument publicId removeChild setAttribute setAttributeNS systemId
getDOMImplementation createDocument createDocumentType
```

...plus, decisively, a reach into a **private minidom internal**:

```python
# html5lib/treebuilders/dom.py:170
# HACK: allow text nodes as children of the document node
if hasattr(self.dom, '_child_node_types'):
    # pylint:disable=protected-access
    if Node.TEXT_NODE not in self.dom._child_node_types:
        self.dom._child_node_types = list(self.dom._child_node_types)
        self.dom._child_node_types.append(Node.TEXT_NODE)
```

html5lib is patching minidom's private class-level list of permitted child
types. A shim would have to reproduce not just the DOM API but a specific
CPython implementation detail that the caller guards with `hasattr` — i.e. the
caller already knows it is reaching into someone's internals.

**This is a real DOM implementation and should be ranked as one**, not as a
shim. It is the honest answer the dispatch asked for: these files want a DOM,
and that is a project.

## Why not even do question 1 — two measurements, either sufficient

### It unblocks nothing

A 20-line `Node`-only shim was written to scratch and measured. All four files
clear the `xml_dom` wall, and land immediately on:

| file | next wall |
| --- | --- |
| `treewalkers/base.py` | `undefined variable (digits)` |
| `treewalkers/dom.py` | `undefined variable (digits)` |
| `treewalkers/etree.py` | `undefined variable (digits)` |
| `treebuilders/dom.py` | `missing module: weakref` |

So `xml_dom` is not a wall — it is *in front of* a wall. Three of the four files
collapse into row 1 (`digits`,
[[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]]),
which is already frank2's ground, and the fourth trades one missing module for
another. **Net files unblocked by shimming `xml.dom` today: zero.** Same
ranking discipline as
[[bug-n-a-unicode-identifier-is-rejected-by-the-lexer]] — rank on measured
unblock, not on how tractable the work looks.

### And it would be silently wrong if written

This is the part that could not have been reasoned to. A class whose definition
is not followed by a module-level statement currently loses its attribute
initialisers and reads every one back as **0**
([[bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero]], found while
measuring this row). A constants-only shim is exactly that shape: one class,
nothing after it.

Note this is *not* avoidable by writing the shim more carefully. Putting a
module-level statement after `class Node` would mask it — and masking it is
worse than hitting it, because the shim would then be correct only by virtue of
a trailing line nobody could explain, and would silently break the day someone
tidied it away.

So the obvious `mimic_xml_dom.py` — 12 constants, no module-level code — would
compile, import, and give `Node.TEXT_NODE == 0`, `Node.ELEMENT_NODE == 0`,
`Node.DOCUMENT_NODE == 0`. Every `nodeType` comparison in html5lib's treewalkers
would then be a comparison of `0 == 0`: **every node would take the first
branch**, silently, and the walker would emit structurally wrong output with no
error anywhere.

That is exactly the "looks present and fails deep inside a caller" failure the
work was scoped to avoid, arriving by a mechanism nobody predicted — and the
only reason it was caught is that the measurement came before the code. A
half-shim is not the only way to build something that looks present; a *complete*
shim on a broken substrate does it too.

## When to revisit

Do question 1 when
[[bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero]] is fixed AND
the `digits` bug is fixed — at which point it is 20 lines and genuinely
complete, and there will be files behind it to unblock. Verify with an assertion
on an actual constant *value* (`Node.TEXT_NODE == 3`), never merely that the
import resolves, since resolving is precisely what it does while returning zero.

Question 2 should be re-filed as its own ranked item if a real DOM is ever
wanted. Do not let it ride along with question 1 under one row.

## Unblocked and reranked 15 -> 55 by the coordinator, 2026-08-18

**Both blockers are now resolved**, and the more important one was fixed today:
`bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero` (`12275b26f`) and
`bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails` are both in
`done/`.

That first fix is why this ticket was correctly refused twice. **A constants class is
exactly the shape that was broken** — a module whose trailing class carries only
class-level attributes read every one of them back as **zero**, silently, with no
diagnostic. `mimic_xml_dom` is precisely that shape: `xml.dom.Node` is twelve integer
constants and no methods. Verified fixed here against CPython:

```
from nodemod import Node
print(Node.ELEMENT_NODE, Node.TEXT_NODE, Node.DOCUMENT_NODE)
   pxx 1 3 9   CPython 1 3 9      (was 0 0 0)
```

**Keep the campaign's scar attached to this ticket**, because this is the file it was
written about: a ~20-line, spec-exact, COMPLETE `mimic_xml_dom` written before that fix
would have compiled, imported cleanly, and made every `nodeType` comparison `0 == 0`, so
every node takes the first branch and the walker emits structurally wrong output with no
error anywhere. Completeness was never the protection — the substrate was. Re-run the
ladder after it lands and check the VALUES, not just that it imports.

Rerank rationale: p15 predates the corpus evidence. `xml_dom` is 4 files on the ladder
and `xml_etree_elementtree` a further 4, which puts it just under
[[feature-b-module-shims-for-the-html5lib-corpus]] (p60) rather than at the bottom of the
board. The refusal recorded in that ticket ("my own earlier refusal, still correct on
v347") was correct when written and is now spent.
