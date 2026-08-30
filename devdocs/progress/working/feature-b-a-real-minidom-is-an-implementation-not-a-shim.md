---
track: B
prio: 20
type: feature
blocked-by: []
summary: "Question 2 of the xml.dom row, re-filed on its own as that ticket said it should be. html5lib/treebuilders/dom.py wants a document you can build and mutate — ~25 DOM methods, getDOMImplementation().createDocument(), weakref.proxy(), and a reach into minidom's PRIVATE _child_node_types. That is a DOM implementation, not a compatibility alias. It unblocks exactly one corpus file and should be ranked as an implementation project, not alongside shims."
status: working
owner: frankB
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

## 2026-08-30 (frankB) — piece 1 landed, and the stated payoff is NOT reachable from Track B

Claimed and worked in pieces, with the CPython differential as each piece's gate.
**The first thing measured was the ticket's own premise, and it does not hold as
written.**

### The wall order, measured against pin v393 — not inherited from this ticket

The ticket presents minidom as what stands between the tree and
`html5lib/treebuilders/dom.py`. Compiling that file says otherwise. In the order
the compiler hits them:

| # | wall | lane | state |
| --- | --- | --- | --- |
| 1 | `import weakref` — *no unit named weakref and no shim mimic_weakref* | **B** | **CLEARED** below |
| 2 | `property(...)` as a builtin NAME — `base.py:321` | **N** | [[bug-n-property-works-as-a-decorator-but-is-not-a-builtin-name]] |
| 3 | `from xml.dom import minidom` binds nothing | **B** | this ticket |

**Wall 2 sits between the two Track B walls.** `@property` as a *decorator*
compiles and works; `property` as a *name* does not exist, so
`v = property(_g, _s)` is `undefined variable (property)`. That is a frontend
gap, filed in N rather than worked around here, per the rule about a library not
routing around a compiler gap.

So this ticket's stated payoff — *"It unblocks exactly one corpus file"* — **cannot
be delivered from Track B at all** while wall 2 stands. Whoever finishes the DOM
should expect the corpus file to stay red, and should not read that as the DOM
being wrong.

**Which changes the gate, and the ticket already anticipated it.** Its own
decomposition says the DOM should be *"tested by value against CPython's minidom
the way the other `mimic_*` differentials are"*. That differential is the real
gate; the corpus file is the motivation. Saying so now rather than discovering it
at the end.

### Piece 1: `lib/rtl/mimic_weakref.py` — `proxy` only, and the refusals are the content

`weakref.proxy(obj)` returns `obj`. The runtime is refcounted with no cycle
collector and no weak-reference support (grepped: nothing in `lib/rtl` or the
compiler implements one), so the reference is strong. Output is identical; the
divergence is a **leak** — `base.TreeBuilder:194` does
`self.document = self.documentClass()` and `dom.py:126` returns
`weakref.proxy(self)`, so `self.document` is `self`, a cycle, one leaked
TreeBuilder per parse. Stated loudly in the file's header because it is the kind
of cost that disappears once a green appears.

**`ref`, `WeakKeyDictionary`, `WeakValueDictionary`, `WeakSet`, `finalize` are
deliberately ABSENT, and two of them are wanted by the corpus** (`weakref.ref`
twice, `WeakKeyDictionary` once, in reportlab). They are refused because a
strong version is silently wrong in the branch-taking way: `ref(x)` exists to
answer `None` once the target dies, so a strong one makes `if r() is None:` take
the wrong branch forever — the same shape as `mimic_xml_dom`'s `0 == 0`
near-miss. `python-compat-tiers.md` asks for exactly this: *"states its subset in
its own header and fails LOUDLY outside it. It never approximates."*

**The loudness was verified, not assumed** — `weakref.ref(t)` gives
`pascal26:5: error: no member ref came of the qualifier weakref`, at the use
site, naming the member.

### Piece 1's gate

`test/lib_mimic_weakref.npy` is a differential: it runs unmodified under CPython,
and both outputs are **byte-identical** (13 lines, 11 checks). It asserts only
what the two interpreters AGREE on — forwarding of reads, writes and calls. The
three divergences (`proxy(x) is x`, `type(proxy(x))`, lifetime) are deliberately
NOT asserted: a differential pins agreement, and asserting a difference would
make the file fail under one interpreter. It is written to still pass unchanged
if `proxy` ever becomes a real weak reference.

### Correction to this ticket's demand list

The surface list above omits `createAttribute`, which `dom.py` calls. Measured
off the file rather than copied forward. Minor, but the list is what the next
piece is sized against.
