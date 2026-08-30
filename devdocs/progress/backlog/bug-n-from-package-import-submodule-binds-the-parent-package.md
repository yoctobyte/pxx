---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`from xml.dom import minidom` binds `minidom` to the PARENT package `xml.dom`, not the submodule. Member lookups then resolve the parent's names silently (`minidom.XHTML_NAMESPACE` returns a string) and fail for the submodule's own (`minidom.getDOMImplementation` -> no member). CPython binds the submodule. The other two spellings work, so this is submodule-as-imported-name specifically, not dotted imports generally."
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
