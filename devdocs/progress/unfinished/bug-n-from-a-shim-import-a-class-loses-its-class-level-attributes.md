---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`from <shim> import Class` then `Class.CONSTANT` is a compile error — `undefined variable (CONSTANT)` — while the SAME file imported as a plain module works, the same shim reached by its literal mimic_ filename works, and the qualified `import shim; shim.Class.CONSTANT` works. So the class object carries its attributes; only the binding produced by a from-import through the mimic_ mapping loses them. Blocks every shim that exports a constants class, mimic_xml_dom included, because the corpus spelling is exactly `from xml.dom import Node` then `Node.TEXT_NODE`."
status: working
owner: frank2-7e
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

## DIAGNOSED 2026-08-18 (frank2-7e) — the shim is INCIDENTAL. Parked, not fixed.

Reproduced at HEAD exactly as filed. Then the framing turned out to be wrong,
and the correct one is simpler and wider.

### THE TITLE AND THE TICKET BLAME THE SHIM. IT IS THE ALIAS.

A plain `as` rename reproduces it with **no shim anywhere**:

```python
import mimic_probe as probe     # ordinary alias, no mimic_ mapping involved
from probe import Node
print(Node.ELEMENT_NODE)        # error: undefined variable (ELEMENT_NODE)
```

The `mimic_` mapping is merely one *producer* of a unit alias (`ParseUsesUnit`
registers `probe -> mimic_probe` in `UnitAliasName` before recursing). Any alias
does it. So the real statement is:

> **`from <alias> import Class`, then `Class.ATTR`, fails — for any unit alias,
> shim-made or `as`-made.**

Retitle when picking this up; the current title sends the reader into the shim
resolver, which is not where the fault is.

### Which statement is at fault — isolated

| program | result |
| --- | --- |
| `import mimic_probe as probe` + **literal** `from mimic_probe import Node` | 1 |
| `import mimic_probe as probe` + **alias** `from probe import Node` | **FAIL** |
| **alias** `from probe import Node` alone | **FAIL** |
| `import probe` + **alias** `from probe import Node` | **FAIL** |
| `import probe` + **literal** `from mimic_probe import Node` | 1 |

The preceding statement is irrelevant in every combination. The trigger is
**the from-import spelled with the alias**, nothing else. Note row 1 and row 2
differ only in the spelling of an already-compiled module.

### It is NOT a class-attribute bug either — narrower than that

Through the very same alias, from the very same unit:

| | |
| --- | --- |
| an ordinary module global (`SOMEGLOBAL`) | **42** ✅ |
| a module function (`somefunc()`) | **7** ✅ |
| constructing (`Node()`) | ✅ |
| `print(Node)` | `<class '__main__.Node'>` ✅ |
| **`Node.ELEMENT_NODE`** | **FAIL** |

So the unit is visible, its symbols resolve, and the class object is fine. Only
the **bare `ClassName.member` form** breaks.

### THREE HYPOTHESES MEASURED AND KILLED — do not retread these

1. **"The uses edge is recorded on the spelling, not the resolved unit"** — the
   shape of `b67db02bb`, and the obvious guess. **Falsified:** adding the real
   edge by also importing the literal name does NOT fix it, and importing the
   literal name FIRST does not protect it either.
2. **"The class is not visible (`DeclVisible` false), so `IsClassType` goes
   false."** **Falsified by direct measurement** — a probe at the resolution
   point prints *identical* state on the failing and working runs:
   `isclass=TRUE flatUCls=105 sym=-1 proc=-1 progsym=-1 curunit=-1`. Same class
   row, same everything. Whatever diverges is NOT this identifier's resolution.
3. **"The unit is marked qualified-only"** (`MarkUnitQualifiedOnly`).
   **Falsified by reading the site:** it fires only for a PASCAL unit reached
   through a NilPy plain `import`, and it gates *routines*
   (`DeclVisibleBareRoutine`), not classes. `mimic_probe` is a `.py` module.

### Where it actually diverges — localised, not yet identified

`ParseFactorCore` reaches the identifier in BOTH runs (probe fires at the
`name := CurTok.SVal` branch with identical state). The working run then reaches
the `STATICM` class-qualifier gate and resolves `Node -> ci=105`. **The failing
run never reaches that gate**, so some branch between the identifier branch and
the class gate claims `Node` first and yields a plain value; `.ELEMENT_NODE` is
then resolved as a member of an untyped receiver (`ParseLValueAST` with
`recvSym=-1`), which is exactly the "undefined variable" the user sees.

Ruled out as the claiming branch: the `.Create` fast path immediately above the
gate (it requires the member to be spelled `Create`/`create`).

**Next step is one bisecting probe run**: probe at descending points between the
identifier branch and the class gate to find which branch exits, then read its
condition — it will be something that differs under an alias while every lookup
above stays identical. All the probe scaffolding used here is described below so
it does not have to be re-derived.

### Reproducing the measurement

`PXXDBG=a.qual` already prints `STATICM`/`MEMBER`/`CTOR`. The extra probes used
here were temporary additions to `parser.inc` (a SHARED file) and have been
**fully reverted** — `git checkout compiler/parser.inc`, rebuilt, fixedpoint
converged, repro still reproduces. Nothing of this diagnosis is left in the tree.
To redo them: print `name/idx/procIdx/IsClassType/FindSym/FindProc/PyProgSym` at
the `name := CurTok.SVal` branch, and guard any `Syms[idx]` print with `idx >= 0`
(`Syms[-1]` aborts the compile mid-probe and looks like a different bug).

### Why parked rather than pushed further

The remaining step is a bisect in `parser.inc`, which is shared with Track A/P
and wants the A/P slot held for a clean run rather than a rushed one. The
diagnosis above is the expensive part and it is banked: the reframing (alias,
not shim), the isolation table, and three dead hypotheses with the measurements
that killed them.

**This still blocks frank3's `mimic_xml_dom`**, and no shim rewrite can dodge it
— the corpus spelling `from xml.dom import Node` IS the failing row, and the
alias is created by the shim mapping itself.

## Relationship to the other three import tickets — MEASURED, and it is a fold

[[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]] (p85)
and frank3's submodule-`as`-rename bug are **the same family**: all are
`from <alias> import ...` binding the wrong thing. This one is now known to be
alias-triggered rather than shim-triggered, which is what puts it in that family.

[[bug-n-a-from-import-of-a-compiler-provided-module-binds-no-names]] (p55) is
**NOT** the same fault and must not be folded: there the from-import resolves and
binds nothing because the root is deliberately consumed-only; here the import
binds fine and only `ClassName.member` breaks. Different mechanism, different
fix. Resemblance is not evidence.
