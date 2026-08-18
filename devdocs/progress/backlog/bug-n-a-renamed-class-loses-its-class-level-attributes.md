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

## SHARPENED 2026-08-18 (frank2-7e) — half of it was silent, and that half is FIXED

Worked as part of the rename cluster. Measuring it turned up a **second,
silently-wrong** symptom that was not in the original report, and that half is
now closed (`3d5ada0d9`).

### The silent half — FIXED

`from M import Node as N2` was registering `N2` as an alias for the whole
**MODULE**, because the guard that skips the submodule-alias registration for a
class asked whether the unit declares a class named `impAlias` (`N2`) when the
class is named `impReal` (`Node`). So:

```python
from mimic_probe import Node as N2
print(N2.somefunc())     # pinned v350: 7   -- CPython: AttributeError
```

It **called the module's function through what is a class and answered 7**. That
is a silent wrong value, the dangerous class, and it is fixed: the guard now
asks about `impReal`. Pinned answers 7, HEAD refuses. Pinned as a refusal in
`test/test_nilpy_renamed_class_is_not_a_module.npy`.

Same root as [[bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes]]
— the same guard, the other argument. That makes **four** instances in one day of
a lookup asking about the wrong name/spelling.

### The reported half — still open, but much better localised

`N2.ELEMENT_NODE` still fails. It no longer fails *silently or as a hijack*
though, and the diagnosis is now specific:

- With the module-alias hijack gone, the class-qualifier gate **does** fire for
  the renamed name and resolves it to the right class row:
  `STATICM name=N2 mem=ELEMENT_NODE qunit=-1 flat=105 -> ci=105`.
- `RegisterUClassAlias` is confirmed called with `real=Node alias=N2 ci=105`, and
  `FindUClassNonRecord` does consult the class-alias registry (its tail scans
  `UClsAlias*`), which is why `N2()` **constructs** correctly.
- What now fails is the **bare-name** resolution of the aliased class: the error
  is `undefined variable (N2)` — the receiver — not `undefined variable
  (ELEMENT_NODE)` as originally filed. So the remaining gap is that the class
  alias is honoured by the class lookups but not by whatever resolves the name in
  value position.

**Start at the bare-name path, not at the attribute lookup**, and note that the
error text in the title/summary above is the OLD one.

### Cluster verdict

Folds with [[bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes]]
(same guard). Does NOT fold with the p85 rebinding bug — that reproduces with no
import and every argument supplied — nor with the callable-value defaults gap.
