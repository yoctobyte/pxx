---
track: N
prio: 45
type: bug
summary: "print() converts a container argument to text as it evaluates it, not after all arguments are evaluated — so `print(xs, xs.pop(), xs)` shows the list before AND after the pop. A user function with the identical shape is correct"
status: done
owner: claude-AN
---

# `print` stringifies container arguments eagerly

- **Type:** bug (NilPy semantics — silent wrong OUTPUT) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle
  (`tools/pydiff.py run`).

## Measured

```python
zs = [1, 2, 3]
print(zs, zs.pop(), zs)        # CPython: [1, 2] 3 [1, 2]
                               # pxx    : [1, 2, 3] 3 [1, 2]
ds = {"a": 1}
print(ds, ds.pop("a"), ds)     # CPython: {} 1 {}
                               # pxx    : {'a': 1} 1 {}
```

Python evaluates all arguments left to right and only then converts each to
text, so both references show the container in its FINAL state. pxx converts the
first argument as soon as it has evaluated it, freezing the pre-mutation text.

## Scope — narrower than it looks, and the controls say why

Everything else with the same shape is CORRECT, which is what pins this on
`print` rather than on argument evaluation or aliasing generally:

| shape | result |
| --- | --- |
| `ys = xs; ys.append(4); print(xs)` — plain aliasing | correct |
| `mut(xs)` mutating through a parameter | correct |
| **`print(xs, xs.pop(), xs)`** — list | **wrong** |
| **`print(ds, ds.pop(k), ds)`** — dict | **wrong** |
| `show(xs, xs.pop(), xs)` — a USER function doing the `str()` | correct |
| `print(str(xs), xs.pop(), str(xs))` — explicit `str()` | correct |
| `[xs, xs.pop(), xs]` — into a list literal, printed after | correct |

So containers are passed by reference correctly; only `print`'s own
argument-to-text conversion happens too early.

## Why it is prio 45 rather than higher

It needs a MUTATING call among `print`'s own arguments, alongside the same
container — uncommon in real code, and it is the kind of line a reviewer would
rewrite anyway. But the failure is silent and in OUTPUT, which is the class of
divergence that erodes trust in a differential run: a corpus diff shows a
mismatch that has nothing to do with the code under test.

## Fix shape

Evaluate every argument of a `print` into its temp first, then convert. The
correct-by-construction version of what the user-function control already
demonstrates — `show(...)` gets this right precisely because the conversion
happens in the callee, after all arguments are bound.

## Gate

A `.npy` diffed against CPython: the list and dict repros; `print` with a
mutating call in FIRST, middle and last position; the user-function and explicit
`str()` controls; plain aliasing as a control; and a mutation of a container that
appears twice with no call between the two mentions.

## 2026-08-02 — cause LOCATED

`PyParsePrint`'s argument loop applies `PyReprContainer(CurASTNode)` to each
container argument **as that argument is parsed**, so the repr call sits in
argument position N of the `AN_WRITELN` chain and therefore RUNS before argument
N+1 is evaluated. That is exactly the observed behaviour: the first `xs` is
converted to text before `xs.pop()` has run.

The user-function control works for the mirror-image reason — `show(xs, xs.pop(),
xs)` binds all three arguments first and the `str()` calls happen in the callee,
after every argument is evaluated. Python's rule, arrived at by construction.

## Why the fix is a restructure, not a line move

The conversion has to happen after ALL argument evaluation, and `AN_WRITELN`
lowers its argument chain in order — so a repr call anywhere in the chain runs
too early. Making it correct means two passes: bind every argument into a temp
first (hoisted assignments, preserving left-to-right evaluation), then build the
writeln over `repr(temp)` nodes.

The loop that would have to change also interleaves separator literals and
handles `end=`, `file=`, `*unpacking`, bare `None`, floats and containers, each
with its own recorded bug behind it. That is a lot of tested behaviour around the
single most-used statement in NilPy, for a divergence that needs a mutating call
among print's own arguments to observe — hence prio 45, and hence not attempted
in the session that found it.

Whoever takes it: the `pargTmp` / `pargAsgn` / `pargTk` locals already declared
in `PyParsePrint` look like the beginning of exactly this temp machinery, and are
worth understanding before adding a second mechanism beside them.


## Resolved 2026-08-04 — the restructure was already there; the ORDER was wrong

The 2026-08-02 note called this "a restructure, not a line move": bind every
argument into a temp first, then build the writeln over the temps. That
restructure **already exists** — and has since before this ticket, added for a
different reason (an argument that RAISES must not leave earlier ones already on
stdout, `bug-nilpy-print-emits-arguments-before-evaluating-later-ones`). Every
print argument is hoisted into a hidden temp.

What was wrong is one line's POSITION. `PyReprContainer` and the float
`pystr_of` routing ran **before** that hoist, so what got hoisted was the
**text**, computed while later arguments had not been evaluated yet:

```
t1 := repr(zs)      <- pre-pop text, frozen here
t2 := zs.pop()
t3 := repr(zs)      <- post-pop
writeln(t1, ' ', t2, ' ', t3)
```

Moving both conversions to **after** the hoist is the entire fix: the temp then
holds the container POINTER, every argument's evaluation has happened by the
time `AN_WRITELN`'s lowering runs, and the repr reads the list as it finally is.

That also explains the control the ticket found most puzzling —
`show(xs, xs.pop(), xs)` doing its own `str()` was always right, because a
callee converts after every argument is bound. The fix makes `print` do the same
thing by construction, which is what the ticket asked for.

### What the temps must still do

Not dropped, and the test pins them: a float still routes through `pystr_of`
(the backend writer and `str()` disagree otherwise), and a string LITERAL must
still widen to a managed string — a `tyString` temp allocates a frozen
STRING_CAP slot, and without the widening `print("a","b","c","d")` reserved
8 MB *per literal*. Measured after the move: that program's BSS is 8324 bytes.

### Verified

`test/test_nilpy_print_arg_eval_order.npy`, wired into `make test-nilpy`: the
list and dict repros, the mutating call in first / middle / last position, the
user-function and explicit-`str()` controls, the list-literal control, plain
aliasing, and the float/literal/bool/None conversions. Diffed against CPython,
identical. `tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit c8093ef11.
