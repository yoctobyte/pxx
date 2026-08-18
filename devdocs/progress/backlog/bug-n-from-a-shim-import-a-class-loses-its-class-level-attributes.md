---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`from <shim> import Class` then `Class.CONSTANT` is a compile error — `undefined variable (CONSTANT)` — while the SAME file imported as a plain module works, the same shim reached by its literal mimic_ filename works, and the qualified `import shim; shim.Class.CONSTANT` works. So the class object carries its attributes; only the binding produced by a from-import through the mimic_ mapping loses them. Blocks every shim that exports a constants class, mimic_xml_dom included, because the corpus spelling is exactly `from xml.dom import Node` then `Node.TEXT_NODE`."
---

# `from <shim> import Class` loses the class's class-level attributes

- **Type:** bug — **Track N** (Nil-Python frontend, shim import path).
- **Found:** 2026-08-18 by frank3-fc, writing `lib/rtl/mimic_xml_dom.py` for
  [[feature-nilpy-xml-dom-is-two-questions-not-one]].
- **Measured against:** `pinned` **v349** (`596799fd9c6e`, pin commit
  `a6e8e763e`) — i.e. WITH today's last-class-hoist and shim-class-visibility
  fixes in. This is a different fault from both.
- CPython accepts and runs every line below.

## Repro

One file, `mimic_probe.py`, reachable as the shim `probe`:

```python
class Node:
    ELEMENT_NODE = 1
    TEXT_NODE = 3
    DOCUMENT_NODE = 9
```

```python
from probe import Node
print(Node.ELEMENT_NODE)      # error: undefined variable (ELEMENT_NODE)
```

## The boundary — the same class, four ways

| spelling | result |
| --- | --- |
| **`from probe import Node` → `Node.ELEMENT_NODE`** | **error: undefined variable (ELEMENT_NODE)** |
| `import probe` → `probe.Node.ELEMENT_NODE` | 1 ✅ |
| `from mimic_probe import Node` (literal filename) → `Node.ELEMENT_NODE` | 1 ✅ |
| identical file as a PLAIN module: `from plain import Node` → `Node.ELEMENT_NODE` | 1 ✅ |
| `from probe import Node` → `Node()` (construct) | works ✅ |
| `from probe import Node` → instance attribute `p.v` | works ✅ |

`plain.py` and `mimic_probe.py` are **byte-identical**; only the name and the
shim mapping differ. So this is not about the class, the attributes, or the
module contents — it is the binding that a from-import produces when it goes
through the `mimic_` mapping. The class object itself is fine, since the
qualified path reads the same constant correctly.

That is a reading of the table; nothing here inspected the resolver.

## Not the same as today's two fixes

Both are IN the binary this was measured on:

- `12275b26f` (last class in a module lost its attrs) — that one silently read
  **0**; this one is a hard compile error, and the plain-module control now
  correctly answers 1 3 9.
- `b67db02bb` (shim classes invisible when two modules import the same shim) —
  the class here is perfectly visible; it constructs and its instances work.

## What it blocks

Every shim that exports a class of constants — which is the whole point of a
constants shim. Concretely:

- `lib/rtl/mimic_xml_dom.py` is written, matches CPython exactly (checked
  programmatically against `xml.dom.Node`, not typed from memory), and cannot
  be landed: the corpus spelling is `from xml.dom import Node` followed by
  `Node.TEXT_NODE`, which is precisely the failing row.
- Four ladder files sit behind it (`treewalkers/base.py`, `dom.py`,
  `etree.py`, `treebuilders/dom.py`).

**Do not "fix" this by rewriting the shim.** The qualified form works, so a
shim author could dodge it — but the failing spelling is in the CORPUS, not in
our code, and the mission is to compile existing source unchanged. There is
nothing to rewrite on our side.
