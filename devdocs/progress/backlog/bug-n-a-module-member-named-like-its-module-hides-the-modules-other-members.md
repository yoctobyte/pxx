---
track: N
prio: 40
type: bug
blocked-by: []
summary: "A module that defines a name equal to its own module name makes every QUALIFIED access to the module's other members fail: `import bisect; bisect.bisect_left(...)` gives `no class declares a method or callable field .bisect_left()`, because `bisect` resolves to the module's member rather than the module. CPython's own Lib/bisect.py has `bisect = bisect_right`, so this is ordinary stdlib-shaped code. From-imports are unaffected."
---

# A module member named like its module hides the module's other members

- **Type:** bug — **Track N** (Nil-Python frontend, name resolution).
- **Found:** 2026-08-18 by frank3-fc while writing `lib/rtl/mimic_bisect.py`
  for [[feature-b-module-shims-for-the-html5lib-corpus]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- CPython accepts and runs this. `Lib/bisect.py` really does end with
  `bisect = bisect_right`, and `import bisect; bisect.bisect_left(a, x)` is
  what every caller writes.

## Repro

`mimic_zz.py`:

```python
def zz_left(a):
    return 1

zz = zz_left          # a member whose name is the module's name
```

```python
import zz
print(zz.zz_left([1]))
# error: Nil Python: no class declares a method or callable field .zz_left()
```

Delete the `zz = zz_left` line and the same qualified call compiles and runs.

## The boundary

| shape | result |
| --- | --- |
| module defines a same-named member; `mod.other_member(...)` | **compile error** |
| module defines no same-named member; `mod.other_member(...)` | OK |
| `from mod import other_member` (module defines a same-named member) | OK |
| `from mod import mod_named_member` | OK |
| module whose ONLY member is the same-named one, called qualified | OK |

Reading that fits every row: at a qualified call the name binds to the imported
member in preference to the module, so `zz.zz_left` looks for `zz_left` on a
function. It is a shadowing question, not a missing-feature one. (Hypothesis —
nothing here read the resolver.)

## Severity, and why it is p40 rather than higher

It is a **compile error**, not a wrong answer, and the from-import spelling —
which is what the corpus actually uses (`from bisect import bisect_left`) —
works. So nothing is silently wrong and nothing is blocked; a caller who writes
the qualified form gets told, if confusingly.

Filed because the shape is common in the stdlib (a module exporting a legacy
alias of its own name), and because the report names a "class" for what is a
module and a function, which sends the reader somewhere unhelpful.

## Track B site

`lib/rtl/mimic_bisect.py` keeps the platonic `bisect = bisect_right` alias, so
`test/lib_mimic_bisect.npy` exercises the module through from-imports only and
says why at the site.
