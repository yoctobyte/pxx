---
track: N
prio: 50
type: bug
blocked-by: []
summary: "Importing a lowercase function and an uppercase class of the same letter from one module breaks the class: `from M import f` plus `from M import F` gives `undefined variable (VAL)` on `F.VAL`, in EITHER order, while importing F alone works. Pre-existing (fails on pinned v351). CPython keeps them apart because it is case-sensitive; the flat namespace here folds case."
status: backlog
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
