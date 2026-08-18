---
track: N
prio: 50
type: bug
blocked-by: []
summary: "Importing a lowercase function and an uppercase class of the same letter from one module breaks the class: `from M import f` plus `from M import F` gives `undefined variable (VAL)` on `F.VAL`, in EITHER order, while importing F alone works. Pre-existing (fails on pinned v351). CPython keeps them apart because it is case-sensitive; the flat namespace here folds case."
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
