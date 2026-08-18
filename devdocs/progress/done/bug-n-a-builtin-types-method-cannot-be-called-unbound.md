---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`list.append(self, x)` / `dict.__getitem__(self, k)` — a BUILTIN type's method called unbound with an explicit self — is `undefined variable (list)`. The same call on a USER class (`A.m(self)`) works. It is how a builtin subclass reaches the base implementation it just overrode, so it is the immediate next wall behind feature-nilpy-subclass-a-builtin-type, and both html5lib sites need it."
status: done
owner: frank2-7e
---

# A builtin type's method cannot be called unbound

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e, landing
  [[feature-nilpy-subclass-a-builtin-type]].
- **Measured at:** HEAD, self-host fixedpoint build, immediately after that
  feature landed.

## Repro

```python
class Stack(list):
    def append(self, x):
        list.append(self, x)      # error: undefined variable (list)
```

The user-class form works and has since
[[bug-nilpy-super-and-unbound-parent-method-calls]]:

```python
class B(A):
    def m(self):
        return A.m(self) + 1      # fine
```

So this is the builtin NAME failing to resolve in a receiver position, not the
unbound-call machinery.

## Why it matters now

Subclassing a builtin landed, and this is what a subclass immediately reaches
for: overriding a method and delegating to the base is the reason to subclass a
container at all. Both html5lib sites are exactly this shape:

| file | line |
| --- | --- |
| `html5lib/treebuilders/base.py:134` | `list.append(self, node)` |
| `html5lib/_utils.py` (`MethodDispatcher`) | `dict.__getitem__(self, key)` |

`treebuilders/base.py` moved onto this wall the moment the base class resolved:
pinned v351 said `unknown base class list`, HEAD says `undefined variable (list)`
at line 134. That is progress ONTO the next wall, not past it.

## Shape of the fix

`PyBuiltinBaseCi` (added by the feature above) already maps `list`/`dict`/`set`/
`bytes` onto their pylib classes for the BASE-CLASS position. The same mapping is
needed where a class NAME is resolved as a receiver — `IsClassType(name)` /
`PyIsClassTypeExact(name)` in the factor paths, several of which live in the
SHARED `compiler/parser.inc`, so this needs the A/P slot.

Deliberately NOT done as part of the feature: it is a separate, nameable
capability (calling a builtin's method unbound), the feature is green and
complete without it, and widening class-name resolution across four shared-file
sites at the end of a session is how a plausible-but-wrong change lands.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus: a `list`
subclass overriding `append` and delegating, a `dict` subclass overriding
`__getitem__` and delegating, and the user-class `A.m(self)` form unchanged.

---

## Resolution (2026-08-18, frank2-7e)

**The probe first, per the collapse the coordinator flagged:** `TPyList.append(self, x)`
— the same call under pylib's own spelling — already compiled and ran. So the
unbound-call machinery was whole and this really was a NAME question, exactly as
the repro above reads. That bounded the job to resolution, not lowering.

It turned out to be **two** name questions, not one:

1. **The receiver name.** `PyBuiltinBaseCi` mapped `list`/`dict`/`set`/`bytes`
   onto their pylib classes in the BASE-CLASS position only. The receiver site is
   `ci := FindUClass(fieldName)` in the shared `compiler/parser.inc` (the
   class-member factor path) — one site, not the four the ticket sized, because
   every other `IsClassType` caller is a construction or typing path that a
   builtin name never reaches. Mapped there too, guarded by **`CurTok.Kind =
   tkDot`** so a bare `list(x)` / `dict()` keeps the conversion-builtin path, and
   by exact lowercase because Python is case-sensitive.

2. **The method name.** Even with the receiver resolved,
   `dict.__getitem__(self, k)` said `class method not found`: pylib spells the
   subscript protocol `fetch`/`store` (TPyDict) and `at`/`put` (TPyList).
   `PyMethNameFor` is the one translator every resolution path is supposed to go
   through — and this path was the one that did not. Routed through it (a no-op
   for any class declaring the name as written, i.e. every user class) and added
   the `__getitem__` / `__setitem__` / `__len__` rows to `PyPylibMethodAlias`
   beside the existing `items`/`keys`/`values` ones.

**Landed:** `compiler/parser.inc` (forward decl + the two edits above),
`compiler/pyparser.inc` (`PyPylibMethodAlias` rows),
`test/test_nilpy_unbound_builtin_method.npy`, wired into `test-nilpy` AND
`test-core` (the block is duplicated in both; a test only in one is uncovered in
the other).

**Verified:** `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.
The new test's output is **byte-identical to CPython 3.12's** on the same file
(`python3 test/test_nilpy_unbound_builtin_method.npy`), which is the oracle that
matters here rather than a hand-written expectation. Covers: `list` subclass
overriding `append` and delegating twice (a silent no-op cannot pass), `dict`
subclass delegating `__getitem__`/`__setitem__`, `set` subclass delegating
`add`, `list.__getitem__` / `dict.__len__`, the user-class `A.m(self)` form
unchanged, and the conversion builtins `list(x)` / `dict({...})` / `set([...])`
un-intercepted.

**NOT verified here:** the two html5lib sites. That corpus is not in this
checkout (it lives in the sibling clones), so what is measured is the two
SHAPES, not those files. Whoever next moves html5lib should expect the wall
after this one to be the ticket below.

**Filed while landing:**
[[bug-n-a-builtin-subclass-subscript-operator-skips-the-override]] — `c[k] = v`
on a `dict` subclass never calls the subclass's `__setitem__`, it lowers
straight to pylib's `store`. The METHOD spelling dispatches correctly, so it is
the operator arm alone. Same family as the feature that created it: the
identity→kind widening handed these instances to the CONTAINER subscript path,
which does not ask about an override, while the user-class arm that does ask no
longer sees them. Two mechanisms, one concept. It is a silent-wrong-value bug,
which is why the test above pins the METHOD spellings and says so in a comment
rather than quietly asserting today's wrong output.

## Log
- 2026-08-18 — resolved, commit 7da43daa9.
