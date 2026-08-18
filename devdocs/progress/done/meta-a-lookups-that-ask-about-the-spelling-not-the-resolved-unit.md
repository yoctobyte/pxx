---
track: A
prio: 60
type: meta
blocked-by: []
summary: "SWEEP of one bug class: a lookup handed a NAME that needs resolving (a shim mapping, a unit alias, an import rename) but asking an alias-BLIND question, or asking about the wrong one of {alias, source name}. Four instances landed in a single day, one of them a silent wrong value. Enumerates every site, says which are correct-as-written and why, and normalises the uses-edge one from three patched paths to a single authoritative site."
status: done
owner: frank2-7e
---

# Lookups that ask about the spelling, not the resolved unit

- **Type:** meta / sweep — **Track A** (resolution-wide; filed under A for
  traceability per the combined-track rule, self-resolved).
- **Opened:** 2026-08-18 by frank2-7e at the coordinator's request, after the
  fourth instance in one day.
- **Scope, deliberately:** enumerate, fix what is wrong, record what is right.
  **Not** a restructuring of name resolution.

## The class

A name written in source is not always the name things are declared under:

| written | actually | producer |
| --- | --- | --- |
| `xml.dom` | `mimic_xml_dom` | NilPy shim mapping |
| `pkga.sub` | `pkga_sub`, then `mimic_pkga_sub` | dotted-package mangling + shim |
| `tk` | `tkinter` | `import tkinter as tk` |
| `N2` | class `Node` | `from M import Node as N2` |

Every one is registered as a **unit alias** (or a class alias), and there are
alias-AWARE lookups for exactly that. The bug class is reaching for an
alias-BLIND one — or asking the aware one about the wrong name.

Its signature is nasty: the QUALIFIED spelling keeps working (a qualifier names
its unit and never consults the visibility-filtered scan), so the failure looks
like it belongs to whatever construct happened to use the flat path. Three of
the four were originally filed as bugs about something else entirely — class
attributes, class visibility, import resolution.

## The four instances (all 2026-08-18)

1. **[[bug-a-a-shim-classes-are-invisible-when-two-modules-import-the-same-shim]]**
   — the uses edge was recorded on the spelling, so the SECOND importer of a
   shim had an edge to a name nothing is declared under.
2. **[[bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes]]** —
   the class-vs-submodule guard asked `FindCompiledUnit(impName)`, and for a
   shim nothing is compiled under the bare module name, so the guard stood down
   for every shim and a class name became a module alias.
3. **[[bug-n-a-renamed-class-loses-its-class-level-attributes]]** (silent half)
   — the same guard, the OTHER argument: it asked whether the unit declares a
   class named `impAlias` when the class carries `impReal`. **Answered 7 where
   CPython raises AttributeError** — the only silent-wrong one, and the reason
   this sweep is worth its cost.
4. **[[bug-n-from-import-with-an-as-rename-loses-what-it-renames]]** (module
   half) — the alias was registered against the module the import was written
   against rather than against what the imported name resolves to.

## Enumeration

Alias-blind unit lookup is `FindCompiledUnit`; the aware one is
`FindUnitOrAlias` (it chases the alias CHAIN, so `ps -> pkga_sub ->
mimic_pkga_sub` resolves in one call). Class lookups have their own pair.

| site | verdict |
| --- | --- |
| `symtab.inc` `FindUnitOrAlias` → `FindCompiledUnit(name)` | **correct** — the fallback *is* the unaliased case |
| `pyparser.inc` `FindCompiledUnit(impAlias) < 0` (submodule guard) | **correct as written**, see below |
| `pyparser.inc` `UnitDeclaresClassExactly(impReal, FindUnitOrAlias(impName))` | **fixed today** (instances 2 and 3 — both arguments were wrong) |
| `pyparser.inc` submodule-alias target | **fixed today** (instance 4) |
| `parser.inc` `RecordUsesEdge(CurrentUnitIdx, strIdx)` | **normalised today**, see below |
| `parser.inc` pyDup arm's own `RecordUsesEdge` | **correct** — it CREATES the alias at that point, so the entry edge could not have resolved it |
| `parser.inc` shim branch (registers alias, re-enters) | **correct** — the recursion records the real edge on its way in |
| `PyFindUnitDotted` | **correct** — `FindUnitOrAlias` plus dotted mangling |
| `ConsumeUnitQualifier` | **correct** — goes through `PyFindUnitDotted` |
| `FindUClass` / `FindUClassNonRecord` | **correct** — both scan `UClsAlias*` after the direct scan |

### Why `FindCompiledUnit(impAlias) < 0` is correct as written

It guards "a real unit already carries this name, so do not hijack its
qualifier". If an ALIAS rather than a unit carries the name, registering a
second entry is harmless: `FindUnitOrAlias` scans the table in order and the
earlier registration wins. **Measured**: `import zed` (a shim) followed by
`from other import zed` still resolves `zed.who()` to the shim. Left alone —
but it is correct for a reason about table ORDER, not because the lookup is
right, so it is worth re-checking if that scan ever becomes last-match.

### The normalisation

`RecordUsesEdge(CurrentUnitIdx, strIdx)` records the SPELLING's edge for every
`uses`. The resolved edge was then added back on three separate paths — the
shim branch's recursion, the already-compiled early exit (instance 1's fix),
and the pyDup arm. **Three mechanisms for one property is the smell**
`devdocs/dev/normalise-dont-special-case.md` names.

Now the single site records both: the spelling's edge and, when the spelling
resolves elsewhere, the real one. It is a no-op on a first load (no alias
exists yet) and fires exactly when the symbols live under another name.

**Verified by removal, not by argument**: instance 1's patch at the
already-compiled exit was deleted and its own regression test stays green,
along with the three later import tests. The pyDup arm is NOT redundant and was
kept — it registers its alias at that moment, after the entry edge ran.

So: two paths where there were three, and the remaining special case has a
stated reason to exist.

## What was NOT found

No fifth live instance. The remaining alias-blind call is the guard above, and
it is safe by table order. Class-side lookups were already alias-aware.

## What this does not cover

The **class**-alias registry is honoured by the class lookups (`N2()`
constructs) but not by bare-name resolution in value position — the open half
of instance 3. That is a different question (which registry a NAME consults),
not an alias-blind unit lookup, so it stays its own ticket.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.
