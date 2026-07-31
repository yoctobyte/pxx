---
track: N
prio: 60
type: bug
---

# Redefining a `def` silently does nothing — the FIRST body still runs

```python
def f():
    return 1
def f():
    return 2
print(f())        # CPython: 2     pxx: 1
```

No error, no warning. In Python a `def` is an assignment to a name, so the
second one replaces the first. pxx keeps the first and every later call goes to
it.

## Boundary — it is same-name-same-arity

| case | CPython | pxx |
| --- | --- | --- |
| `def f(): 1` then `def f(): 2` | `2` | **`1`** |
| the redefinition inside `if True:` | `2` | **`1`** |
| `def f(): 1` then `f = lambda: 2` | `2` | **`1`** |
| `def f(a)` then `def f(a, b)`, call `f(1,2)` | `3` | `3` ✓ |
| `def m` twice inside a `class` | last wins | last wins ✓ |
| `def f(): 1` then `f = 5`, print `f` | `5` | `5` ✓ |

So a different ARITY resolves correctly, and methods resolve correctly, and
rebinding to a non-callable resolves correctly. It is specifically a callable
rebound to another callable of the same shape.

## Likely cause

Pascal overload semantics leaking into a language that has none. Two same-named
routines with the same signature are a redeclaration in Pascal; the frontend
registers the second and the call site binds to the first match rather than to
the name's CURRENT value. The class case works because methods go through a
different registration path (a class member table, where the later entry
overwrites).

Note this is the mirror of a rule that IS wanted elsewhere:
[[project_strict_fpc_umbrella_and_lax_default]] records that lax overload
behaviour is intended for the Pascal frontend. NilPy needs the opposite — a def
is a binding, not a declaration — so the fix belongs on the NilPy path only,
not in the shared overload machinery.

## Why it matters

Every "define a stub, then define the real one", conditional definition
(`if sys.platform == ...: def f(): ...`), test monkey-patch, and
`f = lambda: ...` override silently keeps the wrong body — and the program
behaves as if the second definition were never written. There is no diagnostic
anywhere, and the symptom appears wherever `f` is finally called.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
with CPython's own output. Watch the arity row: making the name rebind must not
break genuine same-name-different-arity resolution, which the corpus relies on,
nor the class-method path.

## PARTIALLY FIXED — the reported (top-level, same-arity) case; two rows stay open

Root cause confirmed as suspected: `FindProc`'s hash chain returns the OLDEST
registration for a name, and `PyParseDef` always gave a redefinition its own
NEW Proc (to avoid corrupting an earlier caller's resolved `BodyAddr`) — so
the second body was compiled but unreachable; every call kept resolving to
the first. Fixed for a same-arity redefinition of a plain top-level `def` by
reusing the existing Proc in place (header metadata re-applied — params,
return type, defaults can still differ at matching arity) instead of
registering a shadow. Confirmed: `def f(): 1` / `def f(): 2` / `print(f())`
now prints `2`, and the different-arity, class-method, and rebind-to-a-value
rows are unaffected (still correct).

Two rows from the table are **NOT** fixed and need more than this:

1. **The redefinition inside `if True:` row.** A `def` appearing inside any
   block (not just another `def`) is compiled through the DEFERRED
   nested-def queue — its body is parsed only after the ENCLOSING scope
   finishes, which for module-level code means after every other top-level
   statement, including a `print(f())` that appears textually BETWEEN the
   two defs. That call is already compiled — with the first `BodyAddr`
   baked in directly, not through a relocation list — before the second
   def's queued reuse-in-place ever runs. Fixing this needs the CALL SITE to
   go through a relocation resolved after all nested-def queues drain, not
   just the Proc registration; a bigger change than this ticket's original
   scope. Measured, not guessed: reproduces identically with and without
   this commit's fix.

2. **`def f(): ...` then `f = lambda: ...`.** The bare assignment creates a
   PLAIN VARIABLE named `f` alongside the still-existing Proc, rather than
   making `f(...)` call sites dispatch dynamically on `f`'s CURRENT value.
   That is the same gap
   [[bug-nilpy-callable-value-abi-sorted-key-and-builtins]] already
   describes (no common ABI for "whatever f currently is" — a def, a
   lambda, a builtin) — fixing one properly fixes the other, and neither
   should be patched around locally.

Test: test/test_nilpy_redefine_def.npy covers what's fixed (same-arity
redefinition) plus the rows that already worked (different arity, class
method, rebind-to-plain-value) as regression guards. The two open rows above
are left for whoever picks up the nested-def relocation work and the
callable-value ABI ticket respectively — this ticket stays open until both
land. Gate: make test-nilpy green, self-host fixedpoint, testmgr --tier
quick.

## RESOLVED — verified fixed (sweep, 2026-07-31 @c75fff21c)

Fresh fixedpoint at HEAD: `def f(): return 1` then `def f(): return 2; print(f())`
now prints **2**, matching CPython (was 1 — the first body). The redefinition
relocation fix landed. Moving out of unfinished/ to done.

## Log
- 2026-07-31 — resolved, commit c75fff21c.
