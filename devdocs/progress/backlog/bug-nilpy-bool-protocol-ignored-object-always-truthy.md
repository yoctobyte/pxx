---
summary: "NilPy: __bool__ and __len__ are ignored in a truth test — every non-nil object is truthy, so `if obj:` takes the WRONG BRANCH silently"
type: bug
track: N
prio: 65
---

# `__bool__`/`__len__` ignored — every object is truthy, silently

- **Type:** bug (NilPy semantics, silent wrong branch) — **Track N**
- **Opened:** 2026-08-01, found by an operator×operand differential sweep against
  CPython (1094 cases).

## Measured (self-hosted binary at `3f2c5b915`)

```python
class C:
    def __bool__(self):
        return False
c = C()
if c:
    print("truthy")
else:
    print("falsy")
print(not c)
```
CPython: `falsy` / `True`. pxx: **`truthy` / `False`.**

And via `__len__`, which CPython falls back to when `__bool__` is absent:

```python
class C:
    def __len__(self):
        return 0
if C(): print("truthy")
else:   print("falsy")
```
CPython: `falsy`. pxx: **`truthy`.**

## Why this is the dangerous class of bug

It does not raise and does not print a garbage number — it silently takes the
**other branch**. An empty custom collection tests as non-empty, a `__bool__`
that means "invalid/unset" tests as valid. Nothing in the output looks wrong.

## Cause — an incomplete fix, not a missing one

This is the unfinished tail of the `not <x>` family recorded in
`project_nilpy_truthiness_keyed_on_handle_family`. `not x` originally
complemented the HANDLE (never nil ⇒ always True) and was fixed three times:

- string → `Length(s) = 0` (`bug-nilpy-not-on-string-always-true`)
- pylib container → `.count = 0` (`bug-nilpy-not-on-container-always-true`)
- **any other object, incl. user classes → `o = nil`**
  (`bug-nilpy-not-on-object-always-true`, 638e4a82e)

That third fix is the one that is wrong in general: `o = nil` is only CPython's
answer for a class defining *neither* dunder. CPython's actual rule is
`__bool__` first, then `__len__() != 0`, then "always true". pxx implements only
the last step.

Consistent with the audit finding that **`__bool__` appears nowhere in
`compiler/**`** (`grep -oh '__[a-z_]*__' compiler/*.inc`), so nothing can be
dispatching it.

## Scope

Every truth context, not just `not`: `if obj:`, `while obj:`, `and`/`or`
operands (note `decide-nilpy-and-or-return-operand-or-bool` — `and`/`or` return
the OPERAND, so the truth test is separate from the result), `bool(obj)`, and a
conditional expression. Fixing only `not` would repeat the three-times-for-one-bug
history above.

## Fix shape

One truthiness helper used by all contexts: dispatch `__bool__` if declared,
else `__len__() != 0` if declared, else the current `o = nil`. The existing
string/container arms stay as they are — they are the same rule specialised for
types whose dunders are known statically.

`__len__` already dispatches (`bug-nilpy-dunder-protocols-ignored-...`), so the
second arm is wiring, not machinery.

## Gate

`make test-nilpy` + self-host byte-identical, and a `.npy` diffed against
CPython covering: `__bool__` False/True, `__len__` 0/non-zero, both declared
(`__bool__` wins), neither declared (non-nil ⇒ truthy), and each truth context
above. Related: [[bug-nilpy-dunders-not-dispatched-through-containers]].

## 2026-08-01 — FIXED for statically-typed receivers; variant receivers remain

### What landed

`PyClassTruthyDunder` (`compiler/pyparser.inc`): `__bool__` if declared, else
`__len__() != 0`, else -1 so the caller keeps its existing answer. Called from
**both** truth contexts — `PyParseBoolNot` (`not x`) and `PyMakeTruthy`
(`if x:`, `while`, `and`/`or`, comprehension filters).

One shared helper deliberately: those two are separate implementations of the
same rule, and that duplication is exactly why the `not <x>` family needed three
separate fixes (string, container, object —
`project_nilpy_truthiness_keyed_on_handle_family`). Anything added to the helper
now reaches both contexts.

`test/test_nilpy_dunder_bool.npy` + `make test-nilpy` wiring; output is
byte-identical to CPython, covering `__bool__` False/True, `__len__` 0/non-zero,
both declared (`__bool__` wins — proven with a class where they disagree),
neither declared, a temporary receiver, and `and`/`or`.

### The boundary, measured

```python
o = BoolFalse()
if o: ...              # local     -> falsy   FIXED
if BoolFalse(): ...    # temporary -> falsy   FIXED
def show(x):
    if x: ...
show(o)                # parameter -> TRUTHY  STILL WRONG
```

An untyped function parameter is a **variant** at run time, so the class is not
known at the point the condition is lowered and compile-time dispatch cannot
fire. Same wall as [[bug-nilpy-dunders-not-dispatched-through-containers]] —
one missing capability (runtime dunder dispatch on a variant), reached here from
a third direction.

That half is **blocked on
[[decide-nilpy-runtime-dunder-dispatch-mechanism]]** and is deliberately NOT in
the regression test; a comment in the test says so, to stop someone adding a
parameter case and finding it red.

So this ticket is fixed for the static case and stays open, reduced in scope, for
the variant case. Reclassify to closed once the runtime-dispatch decision lands
and its implementation covers truth tests.

## 2026-08-01 — mostly fixed; the REMAINING half is `bool()` only, and it is inverted from this title

Re-measured. The `if`/`not` half this ticket is named for now works, and the
residue is narrower and points the other way.

| expression | pxx | CPython |
| --- | --- | --- |
| `if obj:` with `__bool__` → False | falsy | falsy |
| `if obj:` with `__len__` → 3 | truthy | truthy |
| `if obj:` no protocol | truthy | truthy |
| `not obj` (all three) | correct | correct |
| **`bool(obj)`** — any user class | **False** | **True** |

So the title is stale: objects are no longer "always truthy" in conditions;
what remains is that **`bool()` reports every user-class instance as False**,
including ones whose `__len__` says otherwise.

### Cause — `bool()` has no NilPy arm at all, so it mis-binds

`PyMakeTruthy` (`pyparser.inc:1827`) is correct: its user-class arm calls
`PyClassTruthyDunder` (`__bool__`, then `__len__() <> 0`) and falls through to
the raw handle — hence a protocol-less object is truthy in an `if`.

But `bool(x)` never reaches it. Unlike `str(`, which has an explicit NilPy arm
in `parser.inc` (`PyReprContainer`, ~10074), **`bool` has no special case
anywhere** — `grep "'bool'" compiler/parser.inc` is empty. It resolves as a
plain overloaded call into pylib, whose only class overload is

```pascal
function bool(l: TPyList): Boolean; overload;
```

so a user-class handle binds to the **TPyList** parameter and `count` is read
off the wrong object layout. That is
[[bug-a-overload-resolution-ignores-class-identity]] again — the same
unrelated-class-binds-to-class-parameter hole that produced the `dict(pairs)`
segfault.

### Why it cannot be fixed in pylib

Adding `bool(o: TObject)` does not help while resolution ignores class identity:
whichever overload is declared first wins for every class argument, so it would
just move the mis-binding, exactly as measured on `dict()`.

### Fix shape

Two parts, and the first is a prerequisite:

1. **[[bug-a-overload-resolution-ignores-class-identity]]** — otherwise the
   mis-binding stays silent. Note that fixing it ALONE turns this into a compile
   error rather than correct behaviour, because no overload will match a user
   class.
2. **A NilPy arm for `bool(`** in `parser.inc`'s factor, beside the existing
   `str(` one, routing a user-class argument through `PyMakeTruthy` — the shared
   rule the `if` and `not` paths already use, so the three cannot drift again.
   That is the whole point of `PyClassTruthyDunder` existing.

**blocked-by:** [[bug-a-overload-resolution-ignores-class-identity]]

## 2026-08-01 (later) — UNBLOCKED; part 2 is all that remains

[[bug-a-overload-resolution-ignores-class-identity]] is fixed, so `bool(obj)` no
longer silently mis-binds to `bool(l: TPyList)`. It now behaves exactly as this
ticket predicted for that state: with no overload matching a user class it falls
to the variant path, which boxes the handle, so

| class | pxx | CPython |
| --- | --- | --- |
| `__bool__` → False | **True** | False |
| `__len__` → 0 | **True** | False |
| `__len__` → 3 | True | True |
| no protocol | True | True |

i.e. it flipped from always-False to always-True and still never consults the
dunders. Containers (`bool([])`, `bool({})`, `bool("")`) remain correct.

Remaining work is only part 2: a NilPy arm for `bool(` in `parser.inc`'s factor,
beside the existing `str(` one, routing a user-class argument through
`PyMakeTruthy` — the shared rule `if` and `not` already use, so the three cannot
drift apart again.
