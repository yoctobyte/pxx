---
track: N
prio: 60
type: bug
blocked-by: []
summary: "A class in an imported module that is not followed by a module-level statement never runs its class-attribute initialisers: every attribute reads as its type's zero value, no diagnostic. Positional and PER-CLASS, not per-module — in `class K / TOP=1 / class J`, K is correct and J reads zero. So it hits the LAST class in any module. Methods are unaffected; only class-level attribute initialisers are lost."
---

# The last class in a module reads every attribute as zero

- **Type:** bug (module/class initialisation) — **Track N**. May well be core
  lowering rather than the NilPy frontend; filed in N because the construct is a
  NilPy import and N owns `pyparser.inc`. **Not fixable under B.**
- **Found:** 2026-08-17 by frank3, while measuring the `xml_dom` corpus row
  before writing a shim for it — see
  [[feature-nilpy-xml-dom-is-two-questions-not-one]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`); independently
  reproduced by the coordinator on a fresh build at HEAD.
- **Severity:** silent wrong value, no diagnostic, no crash — the expensive
  class per `devdocs/dev/debugging-playbook.md`.

> **This ticket was corrected once. The first version said "a class-only
> module", and said any module-level statement fixed it. Both were wrong; the
> history is in `## What the first version got wrong` at the bottom, because the
> way it was wrong is a reusable warning about measuring.**

## Repro

`nodemod.py`:

```python
class Node:
    ELEMENT_NODE = 1
    TEXT_NODE = 3
    DOCUMENT_NODE = 9
```

`main.npy`:

```python
from nodemod import Node
print(Node.ELEMENT_NODE, Node.TEXT_NODE, Node.DOCUMENT_NODE)
```

```
pxx:     0 0 0
CPython: 1 3 9
```

Strings degrade the same way (`S = "hi"` reads back empty), so the attribute is
being read at its type's **zero value** — the storage exists and was never
initialised.

## The rule, measured

**A class whose definition is not followed by a module-level statement loses its
class-attribute initialisers.** It is positional and **per class**, not per
module:

```python
class K:
    A = 7        # K.A reads 7   -- a module-level statement follows K
TOP = 1
class J:
    A = 9        # J.A reads 0   -- nothing follows J
```

```
pxx:     K.A= 7   J.A= 0
CPython: K.A= 7   J.A= 9
```

So the shape that gets hit is **the last class in a module**, which is an
entirely ordinary way to end a file.

| imported module's body | `mod.K.A` |
| --- | ---: |
| `class K: A = 7` (nothing else) | **0** |
| `class K: A = 7` then `TOP = 1` | 7 |
| `TOP = 1` then `class K: A = 7` | **0** |
| `class K: A = 7` then `print("init")` | 7 |
| `print("init")` then `class K: A = 7` | **0** |
| `class K` + `TOP = 1` + `class J` | K=7, **J=0** |

**Before does not help; only after.** The statement kind does not matter (an
assignment and a `print` behave identically) — position does.

Not the discriminator, each tested and each ruled out: the class name, the
attribute name, the import form (`import m` / `from m import K` / both / through
an instance / dotted `import a.b`), and shim-vs-plain-module. The same class
defined **in the reading file** is always correct — which is why this survives
local testing and only appears once the code moves into a module.

**Methods are unaffected:** a class with only `def`s and no class-level
attributes works fine, whatever follows it. Only attribute initialisers are lost.

## Reading of the cause — NOT verified, do not bank it

Position-sensitivity that is fixed by a *following* statement suggests the
class-body assignments are emitted into module init but the init routine is
truncated at, or generated only up to, the last module-level statement — so
initialiser work attributed to a trailing class falls off the end.

**This is a story, not a measurement.** It was not checked against
`PXXDBG=a.ir:` or the emitted init. Whoever takes this should print what the
compiler actually emits before trusting the paragraph above — and note that the
first version of this ticket also had a confident-sounding cause paragraph built
on a boundary table that was partly wrong.

## Why 60

- **Silent.** No error, no crash, no warning. Constants classes are how DOM node
  types, enum-like flags and status codes are written, and every comparison
  against one silently becomes `== 0`.
- **The last class in a module is a normal way to end a file** — the bug selects
  a shape nobody would think to avoid.
- It blocks writing `mimic_xml_dom` correctly, which is where it was found.

Not 70+ only because no shipped code is currently wrong (see below). That is
luck, and it expires the first time someone writes the obvious constants shim.

## Exposure in our own shims — the corrected answer

The first version of this ticket claimed `lib/rtl/mimic_six.py` and
`lib/rtl/mimic_warnings.py` "escape by accident because they carry module-level
assignments". That reasoning does not survive the corrected rule. Re-checked,
both are safe, for two *different* reasons and neither is the one first given:

- **`mimic_six.py` contains no classes at all** — it is functions and
  module-level constants. Structurally immune.
- **`mimic_warnings.py` ends with `class catch_warnings` at line 94 and its last
  module-level assignment is `_seen = {}` at line 29 — i.e. *before* the class,
  which the corrected rule says does not protect.** It is safe because
  `catch_warnings` has **no class-level attributes**: only `__init__`,
  `__enter__`, `__exit__` and instance state. Methods are unaffected.

So the exposure is real but currently nil, and the guard to remember when
writing any future `.py` shim is: **a class with class-level constants must not
be the last thing in the file** until this is fixed. Both shims' tests pass and
would keep passing either way, so review cannot catch it.

## Gate

The repro prints `1 3 9`. Every row of the rule table above matches CPython,
including `J.A = 9`. Worth a regression test in the dual-runnable form
(`decide-what-an-unwired-test-may-assert`) — the module and the reader are both
legal CPython, so the oracle stays attached to the test rather than being
consulted once.

## What the first version got wrong

Two claims, one root cause in how they were measured.

1. **"A class-only module"** — wrong scope. It is per-class and positional, so a
   module with several classes silently corrupts only the trailing one.
2. **"Any module-level statement fixes it"** — wrong condition. Only a statement
   *after* the class does.

Claim 2 came from a probe whose output was piped through `head -1`. In the two
rows where the module-level statement was a `print`, the print's own output was
the first line, so what got recorded as "the attribute is correct" was really
"the print ran" — **the attribute value was never in the captured output at
all.** The rows were not measured; they were mislabelled.

The coordinator caught it by running the control the table predicted — an
assignment *above* the class — getting `0 0 0`, and reporting the disagreement
instead of assuming its own setup was broken. Worth stating plainly: **the
harness that formats a measurement can silently answer a different question than
the one asked**, and a table row is only as good as the bytes it actually read.
`head -1` on a probe whose output length varies per row is now a known trap.

The one conclusion downstream of the wrong row — "our shims escape because they
carry module-level assignments" — was also wrong, and is corrected above. It
mattered: it was load-bearing for "no shipped code is affected".
