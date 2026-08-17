---
track: N
prio: 60
type: bug
blocked-by: []
summary: "An imported module whose body is ONLY class definitions never runs its class-attribute initialisers: every attribute reads as its type's zero value (0, empty string) with no diagnostic. Adding ANY module-level statement to the same file makes it correct. Silent wrong value, not a crash — a constants-only module is the exact shape this hits, and that is the commonest shape for one."
---

# A class-only module reads every class attribute as zero

- **Type:** bug (module initialisation) — **Track N**. May well be core lowering
  rather than the NilPy frontend; filed in N because the construct is a NilPy
  import and N owns `pyparser.inc`. **Not fixable under B.**
- **Found:** 2026-08-17 by frank3, while measuring the `xml_dom` corpus row
  before writing a shim for it. It is the reason that shim was NOT written —
  see [[feature-nilpy-xml-dom-is-two-questions-not-one]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- **Severity:** silent wrong value, no diagnostic, no crash. Per
  `devdocs/dev/debugging-playbook.md` this is the expensive class — the program
  runs and produces a plausible wrong answer far from the cause.

## Repro

Two files. `e1.py`:

```python
class K:
    A = 7
```

`v.py`:

```python
import e1
print("attr:", e1.K.A)
```

```
pxx:     attr: 0
CPython: attr: 7
```

Strings degrade the same way — `S = "hi"` reads back as the empty string. So the
attribute is being read at its type's **zero value**, not at a garbage address:
the storage exists and was never initialised.

## The boundary — one variable at a time

The discriminator is **not** the class name, the attribute name, the import form,
or the shim-vs-plain-module distinction. All of those were tested and none of them
move it. It is whether the imported module contains **any module-level statement
at all**:

| imported module's body | `mod.K.A` |
| --- | ---: |
| `class K: A = 7` | **0** |
| `class K: A = 7; B = 8` (two attrs, still class-only) | **0** |
| `class K: A = 7` + a method | **0** |
| `class K: A = 7` then `TOP = 1` at module level | **7** |
| `class K: A = 7; B = 8; C = 9` then `T = 1` | **7** |
| `print(...)` before the class | correct |
| `print(...)` after the class | correct |

And the import form is irrelevant — all of these are 0 for a class-only module:

| shape | result |
| --- | ---: |
| `import m; m.K.A` | 0 |
| `from m import K; K.A` | 0 |
| `import m` + `from m import K`, dotted read | 0 |
| `import m; m.K().A` (through an instance) | 0 |
| `import a.b; a.b.K.A` (dotted module name) | 0 |
| the same class defined **in the reading file** | **7 — correct** |

That last row is the one that makes this expensive: the construct works when you
test it locally, and only breaks once you move it into a module.

## Reading of the cause — NOT verified, do not bank it

The pattern says class-body assignments are lowered into the module's
initialisation routine, and that routine is **not emitted or not called** when
the module has no other module-level code — as though "does this module need an
init?" is decided by scanning for module-level statements and a class body is not
counted as one. A module-level `print` runs in both orders, so once an init
exists it is called at the right time; the defect is in deciding whether there
is one.

**This is a story, not a measurement.** It was not checked against
`PXXDBG=a.ir:` or the emitted init. Whoever takes this should print what the
compiler actually emits before trusting the paragraph above — a plausible
unverified cause written into a ticket is this repo's most-repeated mistake, and
this section exists to be deleted and replaced by a measured one.

## Why 60

- **Silent.** No error, no crash, no warning. A constants class is *exactly* how
  DOM node types, enum-like flags, and status codes are written, and every
  comparison against one silently becomes `== 0`.
- **A constants-only module is the commonest shape for a constants module.** The
  file has no reason to contain a module-level statement, so the bug selects
  precisely the files most likely to hit it.
- **Our existing `.py` shims escape by accident, not by design.**
  `lib/rtl/mimic_six.py` and `lib/rtl/mimic_warnings.py` both happen to carry
  module-level assignments (`PY2 = ...`, `_seen = {}`), so both are correct
  today — and a future shim that is *only* classes would be silently wrong with
  nothing in review to catch it. `test/lib_mimic_six.npy` and
  `test/lib_mimic_warnings.npy` pass and would keep passing.
- It blocks writing `mimic_xml_dom` correctly, which is where it was found.

Not 70+ only because no shipped code is currently wrong: nothing in `lib/**` has
the class-only shape today. That is luck, and it expires the first time someone
writes the obvious constants shim.

## Gate

The repro prints `attr: 7`. A class-only module and the same module with a
module-level statement give identical results for every row of the first table
above. Worth a regression test in the dual-runnable form
(`decide-what-an-unwired-test-may-assert`): the file is legal CPython too, so the
oracle stays attached to it.
