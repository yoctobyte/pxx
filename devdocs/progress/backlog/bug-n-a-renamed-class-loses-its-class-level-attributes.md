---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`from mod import Node as N` then `N.ELEMENT_NODE` is `undefined variable (ELEMENT_NODE)`, while the same import without the rename works and `N()` still constructs. Independent of shims and of dotted packages — a plain literal module reproduces it. The class-alias registry gives the new name the class ROW (construction works) but the ClassName.member read path does not follow it."
---

# A renamed class loses its class-level attributes

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e while writing
  the regression test for
  [[bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes]] — the
  rename row was in the test, went red, and turned out to be a different bug.
- **Measured at:** HEAD `6cd63b836`, i.e. WITH that fix in.

## Repro — no shim, no package, no alias mapping

```python
from mimic_probe import Node as N2    # plain literal module name
print(N2.ELEMENT_NODE)                # error: undefined variable (ELEMENT_NODE)
```

## Boundary

| spelling | result |
| --- | --- |
| `from mod import Node` → `Node.ELEMENT_NODE` | 1 ✅ |
| **`from mod import Node as N2` → `N2.ELEMENT_NODE`** | **undefined variable** |
| `from <shim> import Node as N2` → `N2.ELEMENT_NODE` | undefined variable |
| `from mod import Node as N2` → `N2()` construct | works ✅ |

The rename is the whole difference; the shim is irrelevant (it fails with and
without one), which is what separates this from the ticket it was found in.

## Where to look

`from X import NAME as ALIAS` sends a CLASS through `RegisterUClassAlias`
(pyparser.inc) rather than through the `ALIAS = NAME` desugar the value case
uses — the comment there records why: *"A CLASS cannot go through an assignment
(a class held in a variable is not constructible here — measured)"*. That
registry clearly does map the new name onto the same class row, because `N2()`
constructs. So the gap is in the **`ClassName.member` read path**, which resolves
the receiver by name and does not consult the class-alias registry the way the
construction path does.

Same-shaped conclusion as the ticket this came out of: the class object is fine
and only the bare `ClassName.member` form breaks.

## Family

Same family as [[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]]
and frank3's submodule-`as`-rename bug: all are `from ... import ... as ...`
binding something the un-renamed spelling gets right. Worth checking whether one
change closes several — but confirm by mechanism, not by resemblance.
