---
track: N
prio: 68
type: bug
blocked-by: []
summary: "Importing a lowercase function and an uppercase class of the same letter from one module breaks the class: `from M import f` plus `from M import F` gives `undefined variable (VAL)` on `F.VAL`, in EITHER order, while importing F alone works. Pre-existing (fails on pinned v351). CPython keeps them apart because it is case-sensitive; the flat namespace here folds case."
status: done
owner: agent-A
---

# Importing both `f` and `F` from one module loses the class

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e while writing
  the regression test for
  [[bug-n-a-renamed-class-loses-its-class-level-attributes]] — the case-guarantee
  rows went red for a reason unrelated to that fix.
- **Pre-existing:** fails identically on **pinned v351**, so it is not caused by
  today's alias work. Confirmed by running both binaries side by side.

## Repro

```python
# cm2.py
class F:
    VAL = 5
def f():
    return 99
```

| program | result |
| --- | --- |
| `from cm2 import F` → `F.VAL` | **5** ✅ |
| `from cm2 import f` → `from cm2 import F` → `F.VAL` | **undefined variable (VAL)** |
| `from cm2 import F` → `F.VAL` → `from cm2 import f` → `f()` | **undefined variable (VAL)** |

**Either order.** Importing the function anywhere in the file is enough; it does
not have to come first. CPython runs all three — it is case-sensitive, and `f`
and `F` are simply different names.

## Why it is plausibly the same old flat-namespace fold

The from-import machinery folds case in more than one place — the submodule
alias registration does (`InternStr(LowerCase(impAlias))`), and the comment there
already records one victim: *"the alias table folds case, so it claimed the name
`canvas` and beat the MODULE of that name imported later"*. This looks like the
same fold with a class and a function rather than a class and a module. That is
a reading of the shape, **not measured** — whoever takes this should find which
of the case-folding sites is the one, since there are several.

## Scope

Two names differing only in case, exported by one module, both imported. Rarer
than the other import bugs — but `f`/`F` and `parse`/`Parse` pairs do occur, and
the failure is a compile error at the USE site naming the attribute, which points
away from the import that caused it.

## Not the neighbours

- NOT [[bug-n-a-renamed-class-loses-its-class-level-attributes]] (fixed): that
  needed a rename and is about the exactness predicate; this needs no rename and
  fails with the plain declared spelling.
- Related in kind to
  [[meta-a-lookups-that-ask-about-the-spelling-not-the-resolved-unit]] — a name
  answering for a name it should not — but the axis there was alias resolution,
  and here it is case folding.


---

## RE-MEASURED at HEAD 2026-08-19 — much smaller repro, and the title is wrong

Still reproduces at HEAD. But almost every specific in the ticket is incidental,
and the real shape is far narrower. **The exporting module does not need a
case-twin at all**, which is what the title and the whole "flat namespace folds
case" framing are built on.

### Minimal repro — one imported name, one local class, no twin in the module

```python
# cm5.py
def zz():
    return 7
```
```python
from cm5 import zz
class ZZ:                 # declared HERE, not imported
    VAL = 1
print(ZZ.VAL)             # CPython 1;  pxx: undefined variable (VAL)
```

Delete the import line and it compiles. `cm5` contains no class whatsoever.

### What is and is not required

| variation | result |
| --- | --- |
| import `zz`, local `class ZZ`, read `ZZ.VAL` | **fails** |
| same, import placed AFTER the class | **fails** — order-independent |
| import `qq` instead (no case relation) | OK — the case relation is required |
| `import cm5` instead of `from cm5 import zz` | OK — from-import only |
| `zz()` in the same program | **OK** — the import binds correctly |
| `ZZ()` construction, `inst.VAL`, `cm5.ZZ.VAL` | **OK** |
| local `def zz` instead of an imported one | OK |

So: **a from-import of a name that case-folds onto a LOCAL class name breaks
that class's class-level attribute read, and nothing else.** Construction,
instance attributes, qualified access and the imported name itself all keep
working.

### Ruled out by measurement

- **Not symbol/proc case-insensitivity.** `from cm5 import zz` then `ZZ()` with
  no local class gives `undefined variable (ZZ)`, exactly like CPython's
  NameError — imported names are correctly case-sensitive. `DeclCaseSensitive`
  is doing its job.
- **Not `PyStdAliasRecord`** (pyparser.inc:32830), which lowercases both sides
  but bails unless `PyStdProvidesMember` — never true for a user module.
- **Not the alias arm at pyparser.inc:33228**, guarded by
  `(impAlias <> impReal) or (CurrentUnitIdx >= 0)`, so an un-aliased import in
  the main program never enters it.

### Where it goes wrong (measured with `PXXDBG=a.qual`)

```
working:  PXXDBG a.qual MEMBER field=ZZ  flat=0
broken:   PXXDBG a.qual MEMBER field=VAL flat=-1
```

In the working build the receiver `ZZ` reaches the MEMBER arm
(`parser.inc:4819`, `ci := FindUClass(fieldName)` + the `PyIsClassTypeExact`
guard) and resolves to the class. In the broken build the parser never asks
about `ZZ` at all — it has already been consumed as a VALUE by the bare-ident
arm (`parser.inc:13879`), so `.VAL` is then looked up as a member of a variant
and reported as an undefined variable. **The attribute name in the error is a
red herring; the receiver is what mis-resolved** — the same trap
`PyIsClassTypeExact`'s own comment records for the alias case.

### Why I did not fix it

Localised to the interaction, not to a line. The from-import binding path
(`PyParseImportRun`, ~200 lines across several arms) is where the perturbation
originates, and the three obvious candidates above are all measurably innocent,
so finding it needs a proper localization pass rather than a patch. Returning it
unclaimed rather than growing it into a session.

**Next step for whoever takes it:** the question to answer first is why the
presence of a from-import changes which ARM the bare identifier `ZZ` takes at
`parser.inc:13879`, given that `FindSym`/`FindProc` measurably do NOT resolve
`ZZ` to `zz`. Something else the import touches is making the class name look
like a value. Adding a `PXXDBG` line at that site for the NilPy ident arm —
printing `idx`, `procIdx` and the chosen arm — is the cheap instrument, and this
file's own history says to print it rather than reason about it.

Suggest raising prio: this is a silent-ish correctness bug in ordinary code
(`from utils import parser` beside `class Parser` is a routine spelling), not
the narrow two-import curiosity the title describes.


---

## RESOLVED — 2026-08-27, agent-A

Fixed, and the "next step" the previous session wrote is the one that found it:
instrument, do not reason. Three prints settled a cause that four candidate
mechanisms had been (correctly) ruled innocent around.

### Measured

A print of `qUnit` right after `ConsumeUnitQualifier` in `PyParseFactorCore`:

```
broken (with the import):   ZZQUAL name=VAL qUnit=636
working (no import):        ZZQUAL name=ZZ  qUnit=-1
```

`ZZ.` had been **eaten as a unit qualifier**. `name` was already `VAL` by the
time any class arm could look, which is why the earlier session's traces at the
demote guard and the static-member arm never fired at all: the identifier never
reached them. That also explains the error text — `undefined variable (VAL)`
names the ATTRIBUTE while the RECEIVER is what mis-resolved, exactly as the
ticket suspected but could not localise.

### Root cause — TWO folds, and only one of them is the alias table

`ConsumeUnitQualifier` asks `FindUnitOrAlias(name)`. Both tables it consults
store **lowercased** names, and both queries lowercase. So the fold has two
independent sources, and the ticket's title only describes the first:

1. **The alias table.** A from-import registers a MODULE ALIAS for the imported
   name. It cannot tell a submodule from anything else and registers
   optimistically — `from tkinter import ttk` needs exactly that. A guard already
   declined for CLASSES (`UnitDeclaresClassExactly`, added by
   [[bug-n-a-renamed-class-loses-its-class-level-attributes]]); a `def` and a
   module-level assignment were not covered and misfire the same way. Then the
   lowercased alias `zz` also answers for `ZZ`.
2. **The compiled-unit table.** No alias involved: `import canvas` compiles unit
   `canvas`, and `Canvas` — a class imported from elsewhere — folds onto it.
   That is real reportlab code (`from reportlab.graphics.shapes import Canvas`
   beside `from reportlab.pdfgen import canvas`) and the alias guard cannot reach
   it.

The ticket's re-measurement had already shown the exporting module needs no
case-twin, which is what says the fold is in the LOOKUP and not in the import.

### The fix — one per fold

1. **`compiler/symtab.inc`** — `UnitDeclaresClassExactly` grows a sibling,
   `UnitDeclaresNameExactly`: does this unit declare `name`, spelled exactly, as
   a class, a routine **or** a module-level variable — i.e. as something that is
   definitely not a submodule? The from-import registration
   (`pyparser.inc`, ~34805) now asks that instead of the class-only question, so
   the bogus alias is never created. Exact spelling on every arm, for the reason
   the class arm already gives: Python is case-sensitive and the alias table
   cannot represent the distinction, so it has to be made here on the raw
   spelling.
2. **`compiler/pasparser_name.inc`** — `ConsumeUnitQualifier` declines, under
   NilPy, when the name carries an uppercase letter **and** is a class spelled
   exactly. Every unit and alias name in the tables is stored lowercased (checked:
   `FindCompiledUnit` lowercases its query, and all three alias registrations call
   `LowerCase`), so an uppercase letter in the key means any hit was scored by
   FOLDING — a match Python would not make. Fifth site of the family
   `PyIsClassTypeExact` heads.

### Why the guard is restricted to the FOLDED case, and what that cost

The obvious spelling — "an exact class always beats a unit qualifier" — was
written first and **measured to regress a shape that worked**:

```python
class canvas: K = 1
import canvas
print(canvas.WIDTH)      # 612 at the pin; the class-always-wins rule broke it
```

There the class and the module are the SAME Python name, so which wins is a
rebinding-order question this frontend does not model
([[bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it]]). Restricting
the guard to a folded match keeps that shape exactly as it was and makes the
change a pure repair rather than a trade. The reverse ordering (`import canvas`
then `class canvas`, reading `canvas.K`) still diverges from CPython — it did
before this fix too, and it belongs to that rebinding ticket.

### Measured matrix — every row now matches CPython

| shape | before | after |
| --- | --- | --- |
| `from m import zz` (a def) + `class ZZ` → `ZZ.VAL` | `undefined variable (VAL)` | correct |
| same with `zz = 7` (a module VARIABLE) | `undefined variable (VAL)` | correct |
| `from m import f` + `from m import F` → `F.VAL`, either order | `undefined variable (VAL)` | correct |
| `from shapes import Canvas` + `import canvas` → `Canvas.KIND` | `undefined variable (KIND)` | correct |
| `class canvas` then `import canvas` → `canvas.WIDTH` | correct | correct (unchanged) |
| `import canvas` then `class canvas` → `canvas.K` | broken | broken (pre-existing, rebinding order) |
| no case relation / qualified spelling / construction / instance attr | correct | correct |

The whole NilPy import and shim suite was re-run by hand with its real search
paths (`-Futest/nilpy_units`, `-Futest/shims`, the `pkgcorpus` cwd): as-alias,
as-rename, package imports, dotted imports, relative imports, the shim class and
shim-attr tests, the renamed-class pair and the two negative tests all behave
exactly as before. `from tkinter import ttk`-shaped registration is untouched —
the new guard only declines when the exporting unit declares the name itself.

### Filed while here

[[bug-n-a-qualified-module-member-is-taken-by-a-case-folded-local-class]] — the
MIRROR of this bug on the qualified path: `m.zz()` beside `class ZZ` constructs
ZZ and returns the instance. Pre-existing, unchanged by this fix, and silent. It
is in the witness as a commented-out row pointing at that ticket.

### Note on the FPC seed canary

The first green pxx build was RED on the seed: `UnitDeclaresNameExactly` sits
above `StrEqual` in `symtab.inc`, and FPC has none of pxx's declare-anywhere
laxness. A forward beside `DeclVisible`'s — whose comment says this is exactly
the canary that catches it — fixed it, and the binary sha did not change.

### Gate

`make compiler/pascal26` → `self-host fixedpoint: verified — 1 round(s)`.
`tools/gate.sh quick` → GREEN (FPC seed canary included). Witness
`test/test_nilpy_import_case_folds_onto_a_class.npy` + three helper modules
registered in `test-core`, `.expected` generated by CPython, red at pinned v381
and green now.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
