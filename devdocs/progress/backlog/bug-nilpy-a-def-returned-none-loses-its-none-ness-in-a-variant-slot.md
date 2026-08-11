---
prio: 55
track: N
type: bug
blocked-by: []
---

# A def-returned `None` stops being None once it crosses into a variant slot

- **Type:** bug (NilPy, silent wrong value on ordinary code) — **Track N**
- **Found:** 2026-08-11, sweeping shapes while fixing
  [[bug-nilpy-is-none-followed-by-and-or-else-takes-a-generic-compare]].
- **Owner:** —

```python
def fs(i):
    if i > 1:
        return None
    return "ok"

def plain(x):
    return x is None

print(plain(fs(2)))     # CPython True      pxx False
```

Passing a def-returned `None` through an **untyped parameter** — or storing it
in a **list** — loses its None-ness. The receiving `is None` then answers False
on a value that is None.

## The boundary — MEASURED

Each row is `x is None` where CPython says True.

| how the None reaches the test | pxx |
| --- | --- |
| literal: `plain(None)` | **True** ✅ |
| module var read directly: `sv = fs(2); sv is None` | **True** ✅ |
| **untyped param, str-returning def**: `plain(fs(2))` | **False** ❌ |
| **untyped param, int-returning def**: `plain(fi(2))` | **False** ❌ |
| **untyped param, via a module var**: `sv = fs(2); plain(sv)` | **False** ❌ |
| **list element**: `lst = [fs(2)]; lst[0] is None` | **False** ❌ |

Two facts the table pins down:

1. **Not the `and`/`or`/`else` bug.** It reproduces on the bare `x is None`
   with nothing following, which is what separates it from its sibling.
2. **Not str-specific.** The int-returning def fails identically, so this is
   not merely the nil-AnsiString-handle representation. Both of NilPy's typed
   None sentinels — a nil handle for a str, `0` for an int — are being stored
   **raw** into a variant slot without being converted to a `VT_EMPTY` tag.
   A literal `None` is fine precisely because it is built as `PyMakeNone` (a
   real VT_EMPTY variant) at the call site.

So the defect is at the **boxing boundary**: where a statically-typed value
whose type carries a None sentinel is widened into a variant, the sentinel must
become VT_EMPTY. Today the bits are copied and the tag says "string" or "int",
so a `0`-valued int and an `Optional[int]` None are indistinguishable in the
slot — which is the same conflation
[[project_nilpy_variant_object_tag_list_lives_in_four_places]] warns about, one
level down.

## Downstream symptoms already visible

A comprehension filter is wrong, because the loop variable is a variant slot:

```python
vals = [fs(0), fs(2)]
print(len([x for x in vals if x is None]))      # CPython 1   pxx 0
print(len([x for x in vals if x is not None]))  # CPython 1   pxx 2
```

`Optional[T]` values are ordinary in real code (a lookup that may miss, a parse
that may fail), and every one of them that is passed to a helper or collected
into a list currently reads as not-None.

## Suspected shape of the fix

Find the widen-to-variant conversion(s) and make the str and int arms test the
sentinel and emit VT_EMPTY. Expect **more than one site** — that is this
frontend's recurring shape
([[project_nilpy_class_attribute_lowering_matrix]]), and the table above already
shows at least two independent routes (a call argument and a container store)
that would each need it.

Note the risk the sibling ticket recorded: widening decisions around None have
twice caused regressions in the other direction. `test_nilpy_none_str_field` is
the canary.

## Not new
Reproduces identically on the **v257 pinned** binary and on HEAD (`e3f79c0b8`).
Nothing in the 2026-08-11 session caused it; the position had not been asked.

## Gate
The six rows above matching CPython; the comprehension pair; both a str- and an
int-returning source; `make compiler/pascal26` + `tools/gate.sh quick`; and
**`make test-nilpy`** as the family sweep, which anything touching None boxing
requires.
