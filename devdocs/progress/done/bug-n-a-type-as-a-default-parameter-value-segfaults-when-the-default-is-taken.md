---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`def f(c=UserWarning)` segfaults at runtime the moment the default is actually taken — no diagnostic, exit 139. Any TYPE as a default value does it (user class, builtin type, builtin exception), whether or not the parameter is then called; ordinary values are fine. Passing the argument explicitly works, so the fault is in materialising the default."
status: done
owner: frank2
---

# A type as a default parameter value segfaults when the default is taken

- **Type:** bug (silent runtime crash, no diagnostic) — **Track N** (NilPy
  lowering). May turn out to be core; it is filed here because the construct is
  a NilPy default argument. **Not fixed under B.**
- **Found:** 2026-08-17 by frank3, writing `mimic_warnings`, whose CPython
  signature is `warn(message, category=UserWarning, ...)`.
- **Measured against:** `pinned` **v346**. Not re-checked at HEAD.

## Repro

```python
def f(c=UserWarning):
    return c("m")

print(str(f()))          # <-- no argument: the default is taken
```

```
pxx:     Segmentation fault (core dumped), exit 139, no output, no diagnostic
CPython: m
```

## The boundary, one variable at a time

| case | result |
| --- | --- |
| `def f(c): ...` called as `f(UserWarning)` | **ok** |
| `def f(c=UserWarning): ...` called as `f(UserWarning)` — default present but unused | **ok** |
| `def f(c=UserWarning): ...` called as `f()` — default taken | **SEGFAULT** |
| `def f(c=A)` for a user class `A`, called as `f()` | **SEGFAULT** |
| `def f(c=str)` for a builtin type, called as `f()` | **SEGFAULT** |
| `def f(c=UserWarning): return c.__name__` — never *called*, only read | **SEGFAULT** |
| `def f(c=5): return c + 1` | ok |

So it is not about the class being *called*, and not about which class it is:
**materialising a TYPE as a default argument value is what crashes.** Reading
`.__name__` off it is enough. Ordinary values as defaults are unaffected, and
passing the same type explicitly is fine — `bug-n-a-type-name-is-not-a-first-class-value`
made types first-class in value positions, and the default-argument slot looks
like the one position that did not come with it.

## Why it matters more than the construct suggests

1. **It is silent.** No compile error, no runtime message, no partial output —
   exit 139. Every other type-as-a-value gap in this dialect has produced a
   clear diagnostic (`the class W cannot be used as a VALUE yet`,
   `issubclass() takes class NAMES`). This one produces a core dump, which is
   the failure mode this repo's debugging playbook calls the expensive kind.
2. **It breaks NilPy's upward-compatibility contract**: `warnings.warn("x")`
   is ordinary working CPython, and it must work here.
3. `category=SomeWarning` / `cls=SomeClass` is a *very* common Python signature
   idiom — factory functions, `warn`, `raise_for`, serialiser hooks.

## Current workaround, registered

`lib/rtl/mimic_warnings.py` writes `category=None` and substitutes
`UserWarning` inside the body. Registered in
`devdocs/dev/track-b-workarounds.md` with a revert-to note, per the Track B
convention for library code that sidesteps an open compiler bug rather than
hiding it. Revert to `category=UserWarning` when this lands.

## 2026-08-17 (frank2, Track A) — RESOLVED. One hardcoded `False`; the type was a red herring.

Reproduced at HEAD exactly as filed. The boundary table holds, with one row
added: if the default is TAKEN but the parameter is **never read**, it exits 0 —
so the slot holds a bad pointer and touching it is what crashes.

### It is not about types at all

`c is None` segfaults too, so it is not `.__name__`, not calling the class, and
not which class. And a class as a value works **everywhere else** — as a global,
printed, in a list, passed explicitly to the same variant parameter. Only the
default slot crashes.

gdb named it in one line:

    #4 ... in f (c=<error reading variable: Cannot access memory at address 0xb>)

**0xb = 11 = `VT_CLASSREF`.** The callee received the variant's *tag* as the
pointer it dereferences. So the argument was passed BY VALUE where the
parameter is by-reference.

### Root cause

A NilPy variant parameter is passed by reference — the callee reads a 16-byte
slot through a pointer. The written-argument loop computes that (`ir.inc:9175`):

```pascal
isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
```

The **default-fill** path forty lines below did not:

```pascal
value := IRLowerCallArg(cpi, pathIdx, dfltAST, False);   { <-- always False }
```

`IRLowerCallArg` takes the address only when told the parameter is by-ref. With
`False` it LOADED the global, and the load's first 8 bytes are the tag.

Fixed by computing `isRefArg` the same way the written-argument loop does.
**One expression.** The two paths are the same "one concept, two mechanisms,
only one carries the capability" shape as the `@procvar` and method-unpack
findings today.

### Why it presented as "a TYPE segfaults"

Every other default flavour hides the bug:

- a scalar (`b=1`, `b=1.0`, `b=True`) is not a variant, so the scalar→variant
  **boxing** block builds a temp and passes *its* address regardless of
  `isRefArg`;
- `= None` **hand-builds a temp and LEAs it** a few lines below — literally the
  same address-taking done manually, one branch over;
- `b=[]` / `b={}` store a `tyClass` handle, boxed the same way.

Only a default whose hidden global is **already a variant** reaches the load.
And the value that lands there is a class, because
`feature-nilpy-class-as-a-value` boxes one into a `VT_CLASSREF` variant. Hence
the symptom pointed at types when the defect had nothing to do with them.

### Verified — every SEGFAULT row is now ok, against CPython

| case | before | now | CPython |
| --- | --- | --- | --- |
| `f(c=W)` default taken, `c("m")` | 139 | `m` | `m` |
| `c.__name__`, read only | 139 | `W` | `W` |
| `c is None` | 139 | `False` | `False` |
| default via an ordinary global (`c=g`) | 139 | `W` | `W` |
| `c=[]` (must not regress) | `0` | `0` | `0` |
| `c=5` (must not regress) | `6` | `6` | `6` |

**One row is not CPython-equal and is a SEPARATE pre-existing gap, not a
regression:** `def f(c=str): print(c.__name__)` now raises a clean
`AttributeError: 'type' object has no attribute '__name__'`. The identical
top-level spelling `g = str; print(g.__name__)` fails the same way, so
`__name__` on a **builtin** type is simply unimplemented — a Python-shaped
error, not a crash, and out of this ticket's scope. Filing separately.

### Test

`test/test_nilpy_type_as_default_arg.npy`, enumerated in `test-nilpy`. Covers
default-taken, default-overridden, read-without-calling, via-an-ordinary-global,
and the `c=[]` non-regression in one file. Byte-identical to CPython, and
confirmed **exit 139 on a baseline built from HEAD minus this diff** — so it
fails for the real reason rather than by construction.

### Track B: the workaround can be reverted

`lib/rtl/mimic_warnings.py`'s `category=None` + substitute-in-body workaround is
no longer needed — `category=UserWarning` compiles and runs. Not touched here
(`lib/**` is Track B's lane); flagged for revert and for dropping its entry in
`devdocs/dev/track-b-workarounds.md`.

## Gate

The repro above prints `m` and exits 0, and all six SEGFAULT rows in the table
become ok. Then `mimic_warnings`'s signature reverts and its registry entry is
dropped.

## Log
- 2026-08-17 — resolved, commit 31172d1cc.
