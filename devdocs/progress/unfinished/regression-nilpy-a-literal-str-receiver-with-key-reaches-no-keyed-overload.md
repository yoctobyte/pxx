---
prio: 50
track: N
status: unfinished
owner: frankA
---

# regression: a LITERAL str receiver with `key=` reaches no keyed overload

Split out of `regression-test-nilpy-test-nilpy-max-min-iterables`, which fixed the
dict and named-str arms in the library. This arm needs the frontend.

## Measured

Same commit as that regression — `7b73a385d` (the callable→Pointer coercion moved
into `PyBindKwArgs`). At `7b73a385d^` the literal form printed `b`.

```python
def f(k): return len(k)
print(max("bca", key=f))     # LITERAL  -> TypeError: '>' not supported between 'int' and 'str'
s = "bca"
print(max(s, key=f))         # NAMED    -> b        (fixed by the AnsiString overload)
print(max(("b","a"), key=f)) # LITERAL tuple -> compile error, see below
t = ("b","a")
print(max(t, key=f))         # NAMED    -> b        (already worked at 7b73a385d^)
```

Regressed: **literal str**. Pre-existing (fails at `7b73a385d^` too, so NOT part
of that regression): **literal tuple / inline generator expression**, which is
`bug-nilpy-keyword-arg-vs-overload-set` and reports

```
max has no parameter named 'key' in the overload taking 2 argument(s) —
a sibling overload taking 2 does.
```

## Why the library fix does not reach it

`min`/`max` now carry `TPyDict` and `AnsiString` keyed receivers, mirroring
`sorted`. A NAMED str binds to the `AnsiString` overload; a LITERAL does not — the
keyword promoter re-targets on the argument's **static type** (see the comment
above `min(l: TPyList; key…)` in `compiler/builtin/pyeval.pas`: "`min` is picked
from pylib's two-Variant scalar form, and the keyword `key` is what re-targets it
here"). So the literal never becomes a candidate for any keyed overload, and
adding more library overloads cannot fix it — including a `Variant` keyed pair,
which I wrote, measured as buying nothing, and removed.

Fix belongs in `compiler/pyparser.inc` (Track N), alongside
`bug-nilpy-keyword-arg-vs-overload-set` — plausibly the same change, since both
are the promoter choosing by static type before the keyword is considered.

## Guard

`test/test_nilpy_max_min_iterables.npy` covers the named receivers and says in its
header that literals are deliberately absent — do not read it as covering them.
Add the literal rows here when this is fixed.

---

## Diagnosis pass — frankA, 2026-08-30. Narrowed hard, NOT fixed. Parked.

**Three hypotheses killed by measurement, which is the part worth inheriting.**
Each was plausible, each is now excluded, and each exclusion narrows the next
person's search rather than widening it.

### 1. "The keyword promoter re-targets on static type" — WRONG

This is what I wrote in the section above when I filed it, and it is wrong.
A probe in `PyPromoteProcOverloadByKwAt` printing the before/after proc index:

```
print(max("bca", key=f))     PROBE promote max: proc#875 -> proc#1602 on kw=key
s = "bca"; max(s, key=f)     PROBE promote max: proc#875 -> proc#1602 on kw=key
print(max({"b":2}, key=f))   PROBE promote max: proc#875 -> proc#1602 on kw=key
```

**Identical for the failing case, the working case and the dict case.** The
promoter matches on parameter NAME only and is not the discriminator. Whatever
separates them happens after it.

### 2. "A literal arrives as a variant and unwraps into the first-declared class overload" — WRONG

`pyeval.pas` warns that "declaration order decides which class overload a VARIANT
argument unwraps into", which made this the obvious next suspect. Tested by
declaring the `AnsiString` keyed pair BEFORE the `TPyList` pair and rebuilding:

| | before | after reorder |
| --- | --- | --- |
| `max("bca", key=f)` literal | fails | **still fails** |
| `max(s, key=f)` named | ok | ok |
| list / dict receivers | ok | ok |
| `min(v)` / `sum(v)` over a variant list | ok | ok |

Order changes nothing here. (Worth recording separately: the reorder did **not**
reproduce the segfault that comment warns about, so that hazard is either narrower
than written or has since been fixed — do not treat it as a blocker without
re-measuring it.)

### 3. "The callable is coerced to a Pointer and lands in a Variant slot as an int" — WRONG

The failure is `'>' not supported between instances of 'int' and 'str'`, raised by
`PyOperandClashError` with op=9, i.e. `pyvar_gt(int, str)`. An **int** where a
callable or a key-result belongs is exactly what a code address in a variant slot
looks like, and `7b73a385d` moved that coercion into the keyword path — so this
looked strong. It is excluded by reading the routine:
`PyCoerceCallableArgsIn` (`pyparser.inc:21276`) guards **every** arm on
`Procs[procIdx].Params[i].TypeKind = tyPointer`. It cannot write into a Variant
parameter.

### What IS established

- The receiver spelling is the variable: `max("bca", key=f)` fails, `s = "bca";
  max(s, key=f)` works, same program otherwise.
- **The callable spelling matters too, and this is the sharpest clue:**
  `key=lambda c: len(c)` **WORKS**; `key=f` (a def) and `key=len` (a builtin)
  both fail. An inline lambda already lowers to a proc address, so it is
  pointer-typed *before* overload matching; a named callable is a 16-byte variant
  at that moment. So the argument's type at RESOLUTION time is load-bearing, and
  the literal-vs-named receiver difference is likely the same effect on the other
  operand.
- Positional `max("bca", f)` works (it reaches the `PyVarIsCallable` escape in the
  two-Variant overload). Note CPython *rejects* that spelling — our accepting it
  is the known laxness, not a defect.
- The error comes from the two-Variant path (`pyvar_gt(b, a)` with an int `b`),
  which sits oddly beside the promoter evidence that a keyed overload was chosen.
  **Reconciling those two facts is the next step.**

### Next instrument, for whoever takes it

The promoter's answer is not the executed callee — probe the **resolved procIdx at
the call site** (or the emitted call target), not at the promotion. That is the one
measurement that distinguishes "a keyed overload ran and misbehaved" from "a
different overload ran", and every remaining hypothesis lives on one side of it.
The probe technique that worked here: edit the routine, build with
`./compiler/pascal26 compiler/compiler.pas compiler/pascal26_p2` into the
**compiler/ directory** (relative `builtin/` lookup) and run the scratch binary —
no fixedpoint needed, ~2 minutes a turn.

### Why parked rather than pushed further

The fix is in `pyparser.inc`, and Track N is now held by frankB after the owner's
concurrency cut. I have no fix to land, only a narrowed search, so parking beats
opening that file speculatively. Priority unchanged at 50: a literal `str` receiver
with `key=` is real but narrow, and the named spelling works.
