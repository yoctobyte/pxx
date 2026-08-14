# pkgcorpus — a vendored multi-module package fixture

The in-repo stand-in for the neuzelaar corpus, so
`feature-nilpy-dotted-imports-resolve-to-source-files` can be gated here instead
of against a checkout that only one machine has.

**Shaped from what the corpus actually does**, not from what Python allows —
measured over neuzelaar's 168 tracked files on 2026-08-14:

| shape | corpus usage | here |
| --- | --- | --- |
| `from a.b.c import X` (absolute dotted) | the whole population — top hits are `from neuzelaar.document.dom` (35), `from neuzelaar.core.fetch.resource` (26), `from neuzelaar.core.origin` (25) | yes, 2 and 3 segments |
| a subpackage importing another subpackage | pervasive (`document.dom` <- `core.bus`) | yes, `document/dom.py` |
| `__init__.py` that re-exports | 4 files | yes, `mypkg/__init__.py` |
| `import a.b` / `import a.b as ab` | present | yes |
| **relative** (`from .x import`, `from ..y import`) | **ZERO files** | deliberately absent |

That last row is the point of measuring rather than guessing: relative imports
are the shape everyone assumes a package fixture needs, and this corpus does not
contain a single one. They are a separate feature, out of scope for the first
cut, and adding them here would have gated work nothing needs yet.
