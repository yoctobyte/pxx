---
track: B
prio: 20
type: feature
blocked-by: []
summary: "Question 2 of the xml.dom row, re-filed on its own as that ticket said it should be. html5lib/treebuilders/dom.py wants a document you can build and mutate — ~25 DOM methods, getDOMImplementation().createDocument(), weakref.proxy(), and a reach into minidom's PRIVATE _child_node_types. That is a DOM implementation, not a compatibility alias. It unblocks exactly one corpus file and should be ranked as an implementation project, not alongside shims."
---

# A real `minidom` is an implementation, not a shim

- **Type:** feature (library) — **Track B**.
- **Filed:** 2026-08-18 by frank3-fc, splitting
  [[feature-nilpy-xml-dom-is-two-questions-not-one]] as that ticket instructed:
  *"Question 2 should be re-filed as its own ranked item if a real DOM is ever
  wanted. Do not let it ride along with question 1 under one row."*
  Question 1 (`Node`'s twelve constants) is done and shipped as
  `lib/rtl/mimic_xml_dom.py`. This is the other half, standing alone.

## The one caller, and what it actually wants

`html5lib/treebuilders/dom.py` (239 lines) builds and mutates a document:

```
appendChild attributes childNodes cloneNode createComment createDocumentFragment
createElement createElementNS createTextNode firstChild hasAttributes
hasChildNodes insertBefore namespaceURI nodeName nodeType nodeValue normalize
ownerDocument publicId removeChild setAttribute setAttributeNS systemId
getDOMImplementation createDocument createDocumentType
```

plus two things that are not DOM API at all:

- `weakref.proxy(self)` (line 126) — needs a `weakref` module, which does not
  exist here and is a runtime facility rather than a shim.
- a reach into a **private CPython implementation detail** (line 170):

```python
if hasattr(self.dom, '_child_node_types'):
    if Node.TEXT_NODE not in self.dom._child_node_types:
        self.dom._child_node_types = list(self.dom._child_node_types)
        self.dom._child_node_types.append(Node.TEXT_NODE)
```

html5lib is patching minidom's private class-level list of permitted child
types so the document can hold text nodes. The `hasattr` guard says the caller
knows it is reaching into someone's internals. A shim would have to reproduce
not just the DOM but *that specific internal*, under its exact name, for the
guard to fire.

## Why it stays at p15

- It unblocks **one** corpus file, and that file is an optional tree backend —
  html5lib's default treebuilder is `etree`, and `dom.py` is what you get only
  by asking for it.
- It is genuinely large: a conforming-enough DOM plus `weakref`.
- Nothing else in the corpora wants a DOM.

Rank it up if an application wants to build XML documents — that is a real
capability and would be the reason to do it, not this one file.

## What would make it tractable

Not "write minidom". The honest decomposition, if it is ever wanted:

1. `weakref` first, or decide `weakref.proxy` can be identity here and say so
   loudly — it is a lifetime facility, and getting it silently wrong is the
   usual shape of trouble.
2. A DOM core (`Document`, `Element`, `Text`, `Comment`, `DocumentFragment`,
   `DocumentType`) with the node-tree operations, tested by value against
   CPython's minidom the way the other `mimic_*` differentials are.
3. Only then the `_child_node_types` internal, and with a comment saying which
   caller depends on it and why.
