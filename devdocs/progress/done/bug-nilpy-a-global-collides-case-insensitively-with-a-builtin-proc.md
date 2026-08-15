---
track: N
prio: 25
type: bug
blocked-by: []
summary: "Proc lookup is case-INSENSITIVE (Pascal heritage) while Python is case-sensitive, so a NilPy name resolves against a builtin that differs only in case: `print(Counter)` prints 4727019 (a code address) where CPython raises NameError. It also made a nested-def helper claim every read of a global named `counter`."
status: done
owner: claude-AN
---

# A NilPy name resolves case-insensitively against a builtin

```python
print(Counter)     # CPython: NameError: name 'Counter' is not defined
                   # pxx:     4727019          (a code address)
```

Measured 2026-08-15 while triaging
[[regression-test-core-test-nilpy-forward-module-global]], where this was the
substrate the regression stood on: `FindProc('counter')` answered pylib's
`Counter`, so a helper that meant "is there a nested def of this name" got
True for an ordinary module global and every read of it became a function
value.

## Why it happens

`FindProc` lowercases — Pascal's rule, and correct for the Pascal frontend
sharing these tables. NilPy inherits the lookup. Python is case-sensitive, and
the case difference is often exactly what distinguishes a class from a variable
(`Counter` the type vs `counter` the tally), so the collision lands on the
naming convention Python programmers actually use.

## Scope, measured

Reads of a name that IS bound are safe today: the symbol lookup wins first, so
`counter = 7; print(counter)` and a def reading it are both right. What is
exposed is a name with no binding — CPython's NameError — which answers a
builtin of a different case instead. NilPy is upward-compatible with CPython,
so a program that RUNS on CPython cannot observe this; a program with the bug
CPython would have diagnosed gets a silent wrong value instead of a diagnostic,
which is the loss.

## The shape a fix probably takes

The NilPy-facing lookups need a case-SENSITIVE variant, not a global change to
`FindProc` (the Pascal frontend depends on the insensitive one, and the tables
are shared). Candidates: `PyMakeFuncValue`, `PyUserShadowsProc`, the
callable-value arms in `ParseFactor`, and `PyNestedDefOutranksSym`. Check
whether the registered name's own spelling is available to compare against —
if the proc table keeps the source spelling, this is a comparison, not a new
index.

Related to the "own language first" rule: a NilPy name should see NilPy's
namespace before anything the shared table happens to hold.

## Gate

`.npy` diffed against CPython: `print(Counter)` raising NameError; a global
named `counter` read from a def, from a nested def and from a comprehension;
`counter` as a parameter name; and a user def named `counter` still callable.

## 2026-08-15 — half landed, and the remaining route MEASURED

`FindProcExactCase` added to `symtab.inc` — `FindProc` filtered to an exact-case
result. Written on top of the real lookup rather than beside it: FindProc's
exact pass runs FIRST and its case-insensitive fallback only after, so a result
whose stored name differs in case can only have come from the fallback. One
line, and it cannot drift from the visibility / require-forward / unit rules.

Applied to the two NilPy VALUE-position arms — `PyMakeFuncValue` and
`ParseFactor`'s callable-value arm. Measured effect:

```python
x = LEN          # was: a code address.  now: "undefined variable (LEN)"
f = len          # unchanged, still the function value
```

**The remaining route is the CALL path, and it is a bigger change than this
one.** A bare name that resolves as a zero-argument call still matches
case-insensitively:

```python
print(cOUNTER)   # prints {} — it CALLED pylib's Counter()
```

That resolution is the shared Pascal name→proc path in `ParseFactor`, not a
NilPy arm, so making it exact-case for `.npy` only means threading the dialect
through the shared lookup (or registering pylib's NilPy-facing procs
case-sensitively via the `ProcCaseSensitive[]` flag that already exists — which
is probably the better shape, since it says the thing once at registration
instead of at every lookup).

Not attempted here: `ProcCaseSensitive` is read by the Pascal side too, and
flipping it for pylib changes what every Pascal `uses pylib` program resolves.
That is a Track A-shaped decision, not a NilPy-arm edit.

Also worth recording, because it wasted a build: `function F(...): Integer;`
written in the forward block WITHOUT `forward;` does not fail as a syntax
error — every routine after it becomes NESTED inside it, and the failure
surfaces minutes later as "nested routine token buffer overflow" naming a
routine hundreds of lines away.

Back to the backlog with the diagnosis, per root-cause-over-microfix.

## 2026-08-15 — the CALL path landed too; closing

The parked note said the remaining route needed either "threading the dialect
through the shared lookup" or "registering pylib's procs case-sensitively", and
rejected the second because `ProcCaseSensitive` is read by the Pascal side.
Neither was needed. The predicate the frontend already has is `NilPyUserCode`
(symtab.inc), the same one `DeclCaseSensitive` keys on — so the split is drawn
once, at the one bare-name resolution site, without touching registration:

```pascal
if NilPyUserCode then procIdx := FindProcNilPyBound(name)
else procIdx := FindProcBound(name);
```

`FindProcNilPyBound` is `FindProcBound` minus the case-insensitive fallback
**where it reaches Python's own namespace** — a non-exact hit whose
`ProcUnitIdx` names `pylib` or `pyeval` answers -1. Scoped that way on purpose:
the lax rule is what keeps a Pascal RTL routine reachable from NilPy under
whatever case it is spelled with, which `DeclCaseSensitive`'s own comment calls
out as deliberate, and only pylib rows are Python's builtins.

Measured, HEAD vs pinned (the control), `print(<name>)`:

| source | pinned | now | CPython |
| --- | --- | --- | --- |
| `cOUNTER` | `{}` — it CALLED Counter() | refused | NameError |
| `Counter` | code address | code address | NameError |
| `counter = 3; counter` | 3 | 3 | 3 |
| `len` / `print` / `str` | unchanged | unchanged | — |

Swept the mangled-case call forms: `SORTED`, `SUM`, `Len`, `Max`, `REVERSED`,
`Range`, `Zip`, `Enumerate` all refused now.

**Two residues, both deliberately left.** `Counter` bare still answers pylib's
`Counter` because pxx puts `collections.Counter` in the builtin namespace where
CPython requires an import — accepting what CPython rejects, which the
upward-compatibility rule calls a feature, not a defect. And `ABS(-2)` /
`Round(1.5)` / `Chr(65)` / `ORD('a')` still work: those are Pascal SYSTEM
intrinsics, not pylib rows, and they answer the *correspondingly named*
function — a lax spelling of a right answer, never the wrong-value collision
this ticket is about.

Test: `test/test_nilpy_case_sensitive.npy` extended with a global `counter`
read bare, from a def, from a nested def and from a comprehension, `counter` as
a parameter name, and a user def named `counter_fn` — byte-identical to
CPython. Gate: `gate.sh quick` GREEN + self-host fixedpoint; no pin (nothing
under `compiler/builtin/**`).

## Log
- 2026-08-15 — resolved, commit 642d5b98a.
