---
track: N
prio: 65
type: bug
owner: unassigned
blocked-by: []
summary: "`g = f` BOXES the function on the heap; every other path (a dict value, a return value, the bare name) keeps the raw code pointer. So `g == f` and `g is f` are False, two assignments of the same function are unequal to each other, and `id(g)` is a heap address while `id(f)` is the code address. CPython answers True to all of it."
status: done
---

# A function stored in a variable is not equal to the function

- **Type:** bug — Track N (Nil-Python frontend)
- **Opened:** 2026-08-19
- **Filed by:** Track B, writing `lib/rtl/mimic_xml_etree_elementtree.py`
  ([[feature-b-mimic-xml-etree-elementtree-tree-model]]), whose whole risk is a
  function used as a sentinel value. Not Track B's file, so it is handed over.
  CPython answers True to every row below, so by the upward-compatibility rule in
  CLAUDE.md this is an N defect.
- **Measured on:** pinned `stable_linux_amd64/default/pinned` (v352), 2026-08-19.
- **Neighbours:** the callable-value family ([[feature-nilpy-function-values]],
  [[bug-nilpy-def-value-in-a-variable-is-not-callable]],
  [[feature-nilpy-a-callable-value-needs-its-own-variant-tag]]). Those are about
  *calling* a function value; this one is about *comparing* and *identifying*
  one, and nothing in that family covers it.

## The repro

```python
def f(x):
    return x


def ret():
    return f


g = f
d = {"k": f}
```

| expression | pxx | CPython |
| --- | --- | --- |
| `f == f` | True | True |
| `ret() == f` | True | True |
| `ret() == ret()` | True | True |
| `d["k"] == f` | True | True |
| `g == f` | **False** | True |
| `g == d["k"]` | **False** | True |
| `g == ret()` | **False** | True |
| `g is f` | **False** | True |
| `h = f; g == h` | **False** | True |

## The mechanism is visible in `id()`, so it does not need guessing

```
id(f)      6525138            <- a code address (small, static)
id(ret())  6525138            <- same
id(ret())  6525138            <- same, stable across calls
id(g)      133115727052832    <- a HEAP address
id(h)      ...+56             <- a DIFFERENT heap address
```

**Assignment to a variable boxes the function on the heap; every other path keeps
the raw code pointer.** Each `= f` allocates a fresh box (the two heap addresses
above differ by 56 bytes, one allocation apart), and equality compares the box
rather than what it wraps — so a box loses against the bare name and against
every other box.

That also means `id()` of a function is not stable in NilPy, and `is` on a
function is unusable, both of which CPython code is entitled to rely on.

## Why it matters beyond tidiness — the sentinel pattern

CPython's `xml.etree.ElementTree` uses a **function as its own sentinel tag**:
`Comment("x").tag is Comment`, and html5lib compares node tags against it
(`treewalkers/etree.py:16`, `treebuilders/etree.py:21`). Getting that comparison
wrong produces no error at all — comments are simply never recognised and the
walker emits them as elements. The pattern is not exotic: a module-level function
or class used as a unique marker is ordinary Python.

## What is NOT blocked, and why the shim still landed

The identity html5lib actually needs survives, because it never compares against
the module-level name:

```python
sentinel = ET.Comment("asd").tag     # a call RESULT -> raw code pointer
ET.Comment("other").tag == sentinel  # True  (pointer == pointer)
ET.Element("div").tag == sentinel     # False (str vs pointer) -- correct
```

Both sides come from a call result, so neither is boxed and the comparison lands
on the code pointer. Only the variable-assignment path is broken.
`test/lib_mimic_xml_etree_elementtree.npy` therefore asserts the working
spellings and does not assert the broken one — the divergence is recorded here
rather than baked into a test as an expected wrong answer.

## Gate

Track N: every row in the table above answers True, `id(g) == id(f)` for
`g = f`, `make test-nilpy` green, self-host byte-identical. The regression test
must include the *two-variable* row (`g = f; h = f; g == h`) and an `id()`
row — a test comparing only `g == f` could be passed by making the bare name box
too, which would keep two boxes unequal.

## Resolution — 2026-08-27

Fixedpoint `dcc5945d5048`, `tools/gate.sh quick` GREEN.
Test: `test/test_nilpy_function_identity.npy` + `.expected`, registered in the
Makefile. It carries both rows the Gate section demanded — the two-variable
`g = f; h = f` row and an `id()` row — plus the sentinel pattern end to end.
(The `Gate:` line's `make test-nilpy` is superseded by CLAUDE.md's per-fix
loop, `decide-gate-line-convention`.)

**Most of this ticket was already fixed and the table above is stale.** Every
`==` row answers True on current master and did before this change: `pyvar_eqv`
claims a callable pair and compares (code, recv), which is what the comment in
its body describes. Re-measured 2026-08-27, only two of the nine rows were still
wrong, and both on the same axis:

| still wrong | pxx | CPython |
| --- | --- | --- |
| `g is f` (and every other `is` row) | False | True |
| `id(f) == id(f)` | **False** | True |

That `id(f)` was unstable *across two evaluations of the same bare name* is the
tell, and it names the mechanism without guessing: the box is allocated fresh
per evaluation, so identity was comparing two boxes that had never been the same
object. `id(g)` was stable only because the box is stored in the variable.

**Why `is` could not just reuse the `==` fix.** `is` lowers to the SAME tkEq
node `==` does and is told apart only by `PY_BINOP_IDENTITY`; `IRPyVarEqTry`
saw that marker and returned -1, deliberately, so the by-contents claimants
(`pylist_eq`, `pyrange_eq`, `pyvar_eqv`) decline and the pointer compare stands
— which is the whole reason `a is c` on two equal lists answers False
([[bug-nilpy-is-on-two-lists-compares-contents]]). Routing `is` through
`pyvar_eqv` would have undone that.

So identity gets its own claimant, `pyvar_isv`, on the same 0/1/2 protocol:
it answers ONLY for a pair of plain functions, comparing code addresses, and
declines everything else so lists, objects and scalars keep the pointer compare
untouched. `pyid_v` answers the code address for the same shape.

**A bound method is declined on purpose, and the test asserts the `False`.**
CPython builds a fresh bound-method object per attribute read, so `c.m is c.m`
is False there — and the box-per-evaluation behaviour already gives that answer.
Claiming bound methods would have swapped one wrong answer for another. This is
the row a "make functions identity-stable" fix would most easily get wrong.

**Verified unmoved** (all matching CPython): `[1] is [1]`, `l1 = [1]; l1 is l2`,
`s is s`, `5 is 5`, `None is None`, `f is None`, and the whole `==` column.
`test/lib_mimic_xml_etree_elementtree.npy` still passes.

That lib test can now be STRENGTHENED — the note above says it "asserts the
working spellings and does not assert the broken one" because `tag is Comment`
against the module-level name was the broken one. It works now. Left to Track B,
whose file it is.

## Log
- 2026-08-27 — resolved, commit 863092a91.
