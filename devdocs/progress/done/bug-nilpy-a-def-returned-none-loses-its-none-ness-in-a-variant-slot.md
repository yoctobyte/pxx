---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# A def-returned `None` stops being None once it crosses into a variant slot

- **Type:** bug (NilPy, silent wrong value on ordinary code) — **Track N**
- **Found:** 2026-08-11, sweeping shapes while fixing
  [[bug-nilpy-is-none-followed-by-and-or-else-takes-a-generic-compare]].
- **Owner:** claude-AN

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

## 2026-08-11 (same day) — the "boxing boundary" diagnosis above is WRONG for int

Probed the actual variant contents rather than inferring them from `is None`,
using `type(x).__name__` alongside the test:

| value | CPython type | pxx type | pxx `is None` | pxx `str(x)` |
| --- | --- | --- | --- | --- |
| `fs(2)` — str-returning def returns None | NoneType | **str** | False | *(empty)* |
| `fs(0)` | str | str | False | `ok` |
| `fi(2)` — int-returning def returns None | NoneType | **int** | False | **`0`** |
| `fi(0)` | int | int | False | `7` |
| literal `None` | NoneType | NoneType | **True** | `None` |

This splits the ticket into **two different defects**, and only one of them is
at the boundary the section above names:

**(a) str — the information survives, the box drops it.** `fs(2)` yields a nil
AnsiString handle, which is a real None sentinel; read DIRECTLY it works
(`sv = fs(2); sv is None` is True, recorded in the boundary table). It is only
crossing into a variant that loses it: the slot becomes VT_STRING with a nil
payload, and the variant arm of `is None` tests VT_EMPTY. Fixable either at the
box (emit VT_EMPTY for a nil handle) or at the test (treat VT_STRING+nil as
None).

**(b) int — the information is already gone before any box exists.** `fi`'s
return type is INFERRED as int from its `return 7`, so `return None` stores a
plain `0` at the return itself. `str(fi(2))` prints `0`, not an empty slot.
There is nothing left for a boxing-boundary fix to convert, and no test-side
fix can distinguish it from a genuine `0`.

So the earlier framing — "both sentinels are stored raw into a variant slot
without being converted to VT_EMPTY" — is right about (a) and wrong about (b).
The real cause of (b) is **return-type inference**: a def with both `return
None` and `return <int>` must get a nullable/variant return type, not `int`.
That is a typing change, not a conversion change.

### Why this is NOT being half-fixed now
Fixing (a) alone is the classic one-arm-of-a-double-case
(`normalise-dont-special-case`): it would make `plain(fs(2))` correct while
`plain(fi(2))` stayed silently wrong, and the two are indistinguishable in
source. Worse, it would make the bug *harder* to find next time, because the
str spelling — the one people reach for first when reproducing — would start
working.

Banked rather than microfixed, per `root-cause-over-microfix`. The unit of work
is nullable return typing for (b), with (a) falling out of it or fixed
alongside.

### Re-priced
Still prio 55 and still silent, but this is **not** a contained conversion fix
and should not be picked up as one. It is adjacent to
[[feature-n-nilpy-ast-typing-module-scope]] — same "what type does this
expression really have" ground.

## 2026-08-13 — FIXED, as the one typing rule the 08-11 analysis called for

The banked diagnosis was right: (b) is return-type inference, not a conversion,
and fixing (a) alone would have been the one-armed microfix. Both fall out of a
single rule.

`PyInferDefRetType` already widened `sawNone` + tyClass to a variant. That gate
is now kind-blind:

```
if sawNone and (Result <> tyVariant) then   { was: and (Result = tyClass) }
```

A def that returns None on one path and a VALUE on another answers Any, whatever
the value's kind — which is exactly what neither a static int (None became a
plain `0`, indistinguishable from a real zero) nor a static str (a nil handle,
boxed as VT_STRING+nil, which `is None` does not accept) can express. The str
arm's information survived to the box and the int arm's did not, but with the
return declared variant there is nothing left to lose on either.

**The all-bare-return def is in scope too, and needed no extra work.** An
unannotated def is never compiled as a procedure here, so `def f(): return` was
handing back the tyInteger default's 0 and `plain(nothing(2))` said False. A
variant `$pyresult` is zero-initialised, i.e. VT_EMPTY, so it reads as None with
no store at all. That is why the rule is ungated rather than gated on
`PyInferRetSeenAny` — the gated version was written first and left this row
wrong for no benefit.

Every row of both tables in this ticket now matches CPython, including
`type(fi(2)).__name__` = NoneType, `str(fi(2))` = None, and the comprehension
pair.

Gate: `test/test_nilpy_optional_return_is_none.npy` + `.expected` from CPython,
wired into `make test-nilpy` — the six boundary rows, both source kinds, the
comprehension filters, a bare-`return` guard beside a float value, an
all-bare-return def, and the value paths as controls. **`make test-nilpy`
green** (the family sweep this ticket demanded, and the `test_nilpy_none_str_field`
canary is in it), `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
