---
track: N
prio: 55
type: bug
summary: "A user `def sorted(x)` at module scope loses to pylib's builtin — calls go to the builtin and the user's function never runs. Silent: the program produces the BUILTIN's answer"
---

# A user `def` does not shadow a pylib builtin of the same name

- **Type:** bug (NilPy name resolution — SILENT wrong behaviour) — **Track N**
- **Found:** 2026-08-03, while fixing the class half
  ([[bug-nilpy-user-class-named-like-a-pylib-builtin-is-shadowed]]). The class
  half is fixed; this is the same rule for `def`, and it needs a different
  mechanism.

## Repro

```python
def sorted(x):
    return "mine"
print(sorted([3, 1, 2]))     # CPython: mine     pxx: [1, 2, 3]
```

No diagnostic. The user's function is compiled and never called, so the program
quietly produces the builtin's answer — worse than the class case, which at
least failed loudly.

## Why the class fix does not cover it

A user class and a pylib routine are different KINDS of entity, so the class
half is one comparison at the resolution site: a class declared in the main
program (`UClsUnitIdx = -1`) makes the parser drop the proc binding
(parser.inc, the `NilPyUserCode ... FindUClassInUnit(name, -1)` guard).

A user `def` and a pylib routine are both procs, and `FindProc(name)` returns
one of them — by registration order, not by scope. Fixing it means teaching
proc lookup that a main-program declaration outranks a unit one, at least under
`NilPyUserCode`. That is a change to shared resolution machinery and must not
alter Pascal, where a unit routine and a program routine of the same name follow
FPC's rules.

Worth checking at the same time: overloads. pylib's `Counter` is a set of
overloads, so "the user's def wins" has to mean ALL of them lose, not just the
one that ranked best — see [[project_findproc_by_name_ignores_overloads]] for the
adjacent trap.

## Gate

A `.npy` diffed against CPython: a user `def` named after a pylib builtin
(`sorted`, `len`, `str`, `min`) called before and after its definition; one that
shadows an OVERLOADED pylib routine; a control module that does NOT shadow, so
the builtins still work; and the class-shadowing test still green.

## 2026-08-03 — THE CAUSE ABOVE IS WRONG. Measured, and returned to the backlog.

I filed this ticket the same day and guessed the cause from the class half.
The guess — "both are procs, and `FindProc` returns whichever was registered
first" — is **false**, and the counter-measurement is two lines:

```python
def Counter(x):                 # a plain pylib FUNCTION of the same name
    return "mine:" + str(x)
print(Counter(3))               # mine:3 — correct, and correct on PINNED too
```

A user `def` shadowing an ordinary pylib routine **already works**, on the
pinned binary as well as HEAD. So proc-registration order was never the problem.

I implemented the guessed fix anyway (prefer `FindProcInUnit(name, -1)` under
`NilPyUserCode`), built it, and it changed nothing on either program — inert.
**Reverted rather than left in**: unmeasured code that fixes nothing is how a
wrong theory gets a foothold in the tree.

### What is actually happening

`sorted`, `len`, `str`, `int`, `list`, `abs` and friends are **not procs at
all**. They are dispatched by NAME in the parser — an intrinsic lowering keyed
on the spelling, which never consults the symbol table and so cannot notice that
the user declared anything. `Counter` works precisely because it is an ordinary
pylib routine with no intrinsic.

That relocates the ticket entirely:

- the fix is not one comparison at one resolution site;
- it is a guard at every name-keyed intrinsic dispatch — "does the user's module
  declare this name?" — or one predicate consulted before the whole table;
- and it needs the same care as the `__index__` work: a guard applied too
  broadly is how object dict keys got collapsed
  ([[bug-nilpy-unary-numeric-dunders-return-raw-handle]]).

The right shape is probably a single `PyUserShadowsBuiltin(name)` predicate,
checked once at the head of the intrinsic dispatch, mirroring the class rule's
`FindUClassInUnit(name, -1)`. Whoever picks this up: **start by listing the
intrinsic-dispatch sites**, not by reading `FindProc`.

The measured symptom stands unchanged — `def sorted(x)` compiles, never runs,
and the program prints the builtin's answer, silently.
