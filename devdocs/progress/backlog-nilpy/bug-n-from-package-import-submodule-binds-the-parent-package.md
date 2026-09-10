---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`from xml.dom import minidom` binds `minidom` to the PARENT package `xml.dom`, not the submodule. Member lookups then resolve the parent's names silently -- `minidom.XHTML_NAMESPACE` returns `http://www.w3.org/1999/xhtml` where CPython raises AttributeError. STILL LIVE at `ca814b0aabcc` (re-measured 2026-09-10) and still a silent wrong value. BOUNDARY NARROWED: a real filesystem package is CORRECT in all three spellings, measured against a parent and child that both define the same name with different values -- so this is the DOTTED SHIM path (`xml.dom` flattened to `mimic_xml_dom`, trailing name dropped) and not `from <package> import <submodule>` in general. `lib/rtl/mimic_xml_dom_minidom.py` already exists, so the right target is in the tree, unused."
status: backlog
owner: unassigned
---

# `from <package> import <submodule>` binds the parent package instead of the submodule

- **Type:** bug (NilPy frontend, import binding) — **Track N**.
- **Filed:** 2026-08-30 by frankB (Track B), found while building the minidom shim.
- **Measured against pin** `53800fbeb0b66e11`.

## Why this is a bug and not a compat item

CLAUDE.md's compat table sends "CPython accepts a form we reject" to a compat
ticket at whatever prio real usage justifies. This is the row below it: **the
form compiles and then resolves to the wrong object.** For any name that exists
in *both* the package and the submodule, we return the package's silently — no
diagnostic, no crash, a plausible wrong value. That is the silent-wrong-behaviour
escape, so it is filed as a `bug-`.

## Repro

`from <pkg> import <submodule>` is the canonical spelling for minidom — it is
what the CPython stdlib documentation uses — so real code writes it constantly.

```python
from xml.dom import minidom
print(minidom.getDOMImplementation())
```
```
error: no member getDOMImplementation came of the qualifier minidom
       — check what minidom resolves to; an import that bound nothing
         gives exactly this (minidom.getDOMImplementation)
```

The diagnostic's own guess is wrong in an instructive way: the import did not
bind *nothing*, it bound the *parent package*. That is why the suggestion sends
you looking for a missing module rather than a mis-resolved one.

## The boundary — measured, one factor at a time

Against a stub `mimic_xml_dom_minidom.py` exposing `getDOMImplementation()`:

| spelling | compiles | runs | verdict |
| --- | --- | --- | --- |
| `import xml.dom.minidom` then `xml.dom.minidom.getDOMImplementation()` | yes | `42` | **correct** |
| `from xml.dom.minidom import getDOMImplementation` then `getDOMImplementation()` | yes | `42` | **correct** |
| `from xml.dom import minidom` then `minidom.getDOMImplementation()` | **no** | — | **BUG** |

So dotted imports are not broken in general. Two of the three spellings resolve
the submodule correctly; only submodule-as-imported-name does not.

## What `minidom` is actually bound to

Not nothing — the **parent package**. `EMPTY_NAMESPACE` and `XHTML_NAMESPACE`
are top-level names in `xml.dom` (i.e. `lib/rtl/mimic_xml_dom.py`) and are not
minidom's:

```python
from xml.dom import minidom
print(minidom.EMPTY_NAMESPACE)   # -> None                                (xml.dom's)
print(minidom.XHTML_NAMESPACE)   # -> http://www.w3.org/1999/xhtml        (xml.dom's)
```

Both compile and both run. Compare the control `import xml.dom;
print(xml.dom.EMPTY_NAMESPACE)` -> `None` — identical. `minidom` and `xml.dom`
are the same object here.

**This is the part that makes it a bug rather than a missing feature.** Had the
import bound nothing, every use would fail loudly and the ticket would be a
compat item. Because it binds the parent, a program that touches only names the
two modules share gets a wrong answer with no diagnostic anywhere.

## Controls, so the claim is not broader than the evidence

```
from xml.dom import Node          COMPILES, runs   <- real member of the package, correct
from xml.dom import nosuchname    REJECTED: undefined variable (nosuchname)  <- correct
```

A genuine member still binds, and a genuine typo is still caught. The defect is
narrowly the case where the imported name is a **submodule**.

## CPython oracle

```
minidom.getDOMImplementation()   -> DOMImplementation instance
minidom.__name__                 -> 'xml.dom.minidom'
from xml.dom import nosuchname   -> ImportError
```

CPython binds the submodule and agrees with us on the other two rows.

## Suggested shape of the fix

When `from P import N` cannot resolve `N` as a member of `P`, try `P.N` as a
module before falling back — and if it resolves neither, reject. The present
behaviour looks like the fallback is "bind `P` itself", which is the one outcome
that can be silently wrong. Failing loudly here would already be an improvement
over today even without submodule support.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical. Plus the three
spellings in the table above all compiling and running, and both controls
keeping their current behaviour.

## Worth noting for whoever takes it

This is why `lib/rtl/mimic_xml_dom.py` may be seen carrying a `_MinidomNamespace`
shim object binding `minidom` by hand. That is a workaround for this bug, it is
tracked as one, and it should be deleted when this closes rather than left to rot
— see `devdocs/dev/track-b-workarounds.md` for that lifecycle.

# Re-measured 2026-09-10, frankB, compiler `ca814b0aabcc` — STILL LIVE, and the
# boundary is narrower than the title

Reproduces exactly, and the compiler says so itself in a note nobody was reading
as a diagnosis:

```
$ pascal26 xmldom.npy
note: xml_dom -> mimic_xml_dom (shim, subset)
ok: ...
```

`from xml.dom import minidom` bound **`xml.dom`**. The proof that it is the
parent and not a coincidence is a value only the parent has:

| | pxx | CPython |
| --- | --- | --- |
| `minidom.EMPTY_NAMESPACE` | None | None |
| `minidom.XHTML_NAMESPACE` | `http://www.w3.org/1999/xhtml` | **AttributeError** |

CPython: *"module 'xml.dom.minidom' has no attribute 'XHTML_NAMESPACE'"*. We
answer the PARENT's attribute through the CHILD's name, silently. Still a silent
wrong value; the severity claim on this one has NOT decayed.

**`lib/rtl/mimic_xml_dom_minidom.py` EXISTS.** The correct target is sitting in
the tree unused, so this is a resolution bug and not a missing shim.

## What a real filesystem package does — the control that nearly closed this
## ticket wrongly

A package with a parent and child that BOTH define `WHO` with different values,
so a parent-binding cannot hide:

| spelling | pxx | CPython |
| --- | --- | --- |
| `from parpkg import child` then `child.WHO` | child | child |
| `import parpkg.child` then `parpkg.child.WHO` | child | child |
| `import parpkg.child as c` then `c.WHO` | child | child |

**All three correct.** So the defect is NOT in `from <package> import
<submodule>` generally — it is in the DOTTED SHIM path, where `xml.dom` is
flattened to `mimic_xml_dom` and the trailing name is dropped rather than
carried into `mimic_xml_dom_minidom`.

That distinction is the reason this ticket is still open. A green probe on the
wrong path is indistinguishable, afterwards, from a green probe on the right
one: three correct spellings against a discriminator built so a wrong binding
could not hide is more evidence than most closes get, and it was evidence about
a different mechanism. The title should say `shim` where it says `package`, and
whoever takes it should re-derive that boundary rather than trust this table.
