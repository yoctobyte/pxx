---
track: N
prio: 70
type: bug
---

# NilPy: a class-typed field loses its class identity

Found 2026-07-19 chasing the `uforth.py:190` wall (`t.word.name.upper()`).
Silent — prints a raw object pointer, no diagnostic.

```python
class Inner:
    def __init__(self, name: str) -> None:
        self.name = name

class Outer:
    def __init__(self, inner: Inner) -> None:
        self.inner = inner

o = Outer(Inner("dup"))
print(o.inner.name)     # CPython: dup     pxx (before): 4266336
```

## Part 1 — FIXED (commit below)

`PyRegisterClassMembers` registered every `__init__`-assigned field with
`AddUField(..., REC_NONE)`, so a `tyClass` field carried no class identity and
a second-level access could not resolve: `o.inner.name` fell back to Integer
and printed the pointer. The dataclass path already got this right via
`PyAnnLastCi`; `PyRecFromTokenIndex` / `PyHeaderParamRec` give the
`__init__`-annotation path the same. Covered by
`test/test_nilpy_class_field_identity.npy`, diffed against CPython.

## Part 2 — FIXED (see the "resolved" section at the end)

Kept for the diagnosis trail; the ordering problem described below was real and
is now solved.

### (historical) the ORDERING problem

Two siblings remain, both silent:

```python
x = o.inner          # local hop
print(x.name)        # pxx: 4266158

print(o.inner.shout())   # method on a class-typed field: garbage
```

Root cause, measured (not guessed) by instrumenting `PyInferExprType`:

- `PyRegisterClassShells` (pyparser.inc) pre-registers class **NAMES ONLY**.
- `PyCollectModuleLocals` runs at pyparser.inc ~2644, **before** the main loop
  that calls `PyRegisterClassMembers` (~2469).
- So at module-local inference time `FindUClass('Outer')` correctly returns 1,
  but `UClsFCount[1]` is **0** — no class has any field yet. Instrumented
  output: `ciInner=0 ciOuter=1 fcOuter=0 fcInner=0`.

**Do NOT try to fix this by walking field chains during inference** — that was
attempted and reverted; there is nothing to walk. The class index was never
stale (a second wrong theory, also disproved: `o.RecCi` was already correct).

## Fix shapes

1. **Field pre-scan.** Extend `PyRegisterClassShells` to register FIELDS as well
   as names, before `PyCollectModuleLocals`. Watch two hazards: the
   `__init__` path guards with `if FindUField(ci, ...) < 0` and so is
   re-entrant, but the **dataclass path Errors on a duplicate field**, and
   `PyRegisterClassMembers` resets `UClsFBase`/`UClsFCount` on entry, so a
   naive second call re-registers into a fresh window
   (cf. `project_uclass_empty_window_rebase_fix`).
2. **Move module-local collection later.** Blocked by the comment at its call
   site: it must run after the `uses` units so proc return types resolve — and
   classes are parsed interleaved with statements in the main loop, so it
   cannot simply be hoisted.

(1) is the smaller change and is recommended.

## Why it is urgent

uforth is built on object graphs (12 `@dataclass`, `Word`/`WordCall` chains).
`t.word.name` is the `uforth.py:190` wall itself. Part 1 unblocks the direct
chain; the local hop and method-on-field still silently yield garbage, so any
corpus run touching them is untrustworthy.


## RESOLVED 2026-07-19

Part 2's local hop is fixed. Two changes, both needed:

1. **`PyRegisterClassFieldsPrepass`** — walks the token stream for class
   headers and registers each class's FIELDS via `PyRegisterClassMembers` in a
   new `fieldsOnly` mode, BEFORE `PyCollectModuleLocals`. Sharing the one
   procedure keeps the field rules in a single place instead of a drifting
   copy; `fieldsOnly` skips `RegisterProc`/`AddUMeth`/virtual-slot assignment/
   the `PyDc*` bookkeeping/dataclass ctor synthesis. The later real pass resets
   each class's field window and rebuilds it, so the pre-pass entries are
   orphaned rather than duplicated — which also keeps the dataclass
   duplicate-field check from mis-firing.
2. **`RecName` propagation at the module-level assignment** — the site set
   `Syms[symIdx].RecName` for a ctor call and a class-returning call but not
   for any other class-valued RHS, so `x = o.inner` declared the local with no
   class. Now falls back to `ResolveNodeRec(rhsNode)`.

With the pre-pass in place the inference-time field-chain walk became viable
and is restored (it is what gives the local its class identity during
`PyCollectModuleLocals`).

**The third symptom was a DIFFERENT BUG.** `o.inner.shout()` is not a field
problem at all: a method returning `str` yields garbage even on a plain local
with no field involved, and it reproduces on the PINNED compiler. Split out as
[[bug-nilpy-method-returning-str-garbage]].

Note for whoever touches this file next: FPC needs declaration-before-use, so
the pre-pass must stay BELOW `PyFindBodyEnd` and `PyRegisterClassMembers`. pxx
does not care; FPC bootstrap does ([[feedback_fpc_bootstrap_advisory_invisible_to_local_gate]]).

Gate: `test-nilpy` GREEN, `--tier quick` GREEN, self-host byte-identical, FPC
bootstrap clean with a byte-identical fixedpoint, test file diffed against CPython.
