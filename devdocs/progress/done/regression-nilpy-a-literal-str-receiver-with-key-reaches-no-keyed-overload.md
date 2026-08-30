---
prio: 50
track: N
status: done
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

---

## The callee, measured (2026-08-30) — it reaches no `min`/`max` overload at all

Earlier notes here inferred the destination from the error text. It is now
**named**, by tagging every implementation arm with a `writeln` marker and
running the shapes (both `pyeval.pas` and `pylib.pas` are consumed when compiling
a `.npy`, so this probe costs a test recompile, not a compiler rebuild — and both
files were restored and verified clean afterwards, `git diff` empty):

| shape | arm actually entered | result |
| --- | --- | --- |
| `max(s, key=...)` NAMED receiver | `max(const s: AnsiString; key: Pointer)` -> `max(l: TPyList; key)` | correct |
| `max("bca", key=None)` | **`max(const a: Variant; const b: Variant)`** (`pylib.pas:10062`) | TypeError |
| `max("bca", key=f)` named def | **`max(const a: Variant; const b: Variant)`** | TypeError |
| `max("bca", key=lambda c: c)` | (keyed path) | correct |

So the literal receiver does not merely miss the *keyed* overload — it never
reaches any `min`/`max` receiver overload. The `key=` keyword is **positionalized**
into the two-argument scalar form, i.e. `max("bca", <the key itself>)`, and the
`int` vs `str` in the message is the string being compared against the key value.
That also explains the older `expected a number, got object` spelling: same
callee, different second argument.

## The axis is narrower than this ticket's title

| receiver | `key=None` | `key=k` (var) | `key=f` (named def) | `key=lambda ...` (inline) |
| --- | --- | --- | --- | --- |
| literal `"bca"` | FAIL | FAIL | FAIL | **ok** |
| named `s` | ok | ok | ok | ok |

The inline lambda is genuinely correct, not accidentally so: checked with an
*inverting* key (`key=lambda c: -ord(c)`), where the keyed and unkeyed answers
differ — pxx returns `a`, CPython returns `a`. A control whose two answers
coincide would have proved nothing here
(`a-control-from-the-same-idea-as-the-fix-tests-the-idea`).

So the trigger is **literal receiver AND a key that is not an inline lambda**.
Whatever routes an inline lambda to the keyed path is the thing the other three
key forms miss; `PyPromoteProcOverloadByKwAt` (matches on parameter NAME only)
and `bug-nilpy-keyword-arg-vs-overload-set` are where to start.

**Now ranked at 70 by propagation** — it blocks
`regression-test-nilpy-test-nilpy-min-max-key-none` (p70), whose row 4 is exactly
this shape.

*Not attempted in this session: the fix is in the frontend, and the session's
remaining budget went to a fleet-wide FPC seed break.*

---

## Resolved — the literal's MATCH TYPE, confirmed against the matcher

**The cause is not what this ticket's title says.** A literal receiver does reach
the keyed overload set; it is outranked on the way there.

### The discriminating control

`sorted("cab", key=f)` **works** with a literal receiver. `sorted`'s overloads
are all `key: Pointer` with no competing two-argument numeric sibling. So
`tyString` matches an `AnsiString` parameter perfectly well, and the literal's
type is not by itself the defect — that kills the obvious wrong answer.

### Confirmed against the matcher, not inferred from it

Temporarily renamed pylib's `max(const a: Variant; const b: Variant)` out of the
overload set and re-ran the failing shape:

```
max("bca", key=f)   with the two-arg Variant catch-all present -> TypeError
max("bca", key=f)   with it renamed away                       -> c   (correct)
```

So the keyed `AnsiString` overload was reachable and correct the whole time, and
the two-argument **numeric** form was winning the rank. That is the matcher
agreeing, rather than a mechanism that merely explains the rows.

### Why only a LITERAL, and only for min/max

A NilPy string **literal** node carries `ASTTk = tyString`; a str-valued **name**
carries `tyAnsiString`. Same value, two match types. An inexact `tyString`
receiver is enough for the catch-all `(Variant, Variant)` sibling to outrank the
overload that was meant — and `min`/`max` are the only builtins carrying such a
sibling (`PyStarIsIterableForm`'s note calls them the two-entry exception).
`sorted` has none, so it never showed the defect.

Every non-literal spelling of the same value already worked, which is what shows
it is the literal's TYPE and not its value: `"bca" + ""`, `str("bca")`,
`"bca".upper()` — all correct before this fix.

### Fix

`compiler/pyparser.inc`, both arg-type passes of the free-call path: a string
literal argument is reported as `tyAnsiString` rather than `tyString`. NilPy has
no `string[N]` syntax, so a literal can only mean the AnsiString the rest of the
surface presents — **normalise the two shapes into one rather than grow a second
ranking path** (`devdocs/dev/normalise-dont-special-case.md`). Conditioned on the
node shape `AN_STR_LIT`, so a genuine `string[N]` value reaching this path from a
Pascal unit is untouched.

### Verified

All 22 probe shapes match CPython, including every row of the ticket's own table:

| receiver | `key=None` | `key=k` (var) | `key=f` (named def) | `key=lambda` |
| --- | --- | --- | --- | --- |
| literal `"bca"` | ok | ok | ok | ok |
| named `s` | ok | ok | ok | ok |

`test_nilpy_min_max_key_none` now PASSES end to end — it failed at row 4
(`min("cab", key=None)`) before this change and at row 2 before the library fix,
so the two defects are separately demonstrated on separate binaries. Neighbours
green against the CPython oracle: `sorted_key_dispatch`, `sorted_dict_key`,
`sorted_sequences`, `sorted_pairs`, `sorted_key_none`, `list_sort_key`,
`max_min_iterables`, `str_methods`. Self-host fixedpoint converged
(`9946ebdbf7c6`); `tools/gate.sh quick` GREEN; forwardlint exit 0.

### Still open, and NOT closed by this

`max(("b","a"), key=f)` — a literal **tuple** receiver — still fails to compile
with *"max has no parameter named 'key' in the overload taking 2 argument(s)"*.
That is `bug-nilpy-keyword-arg-vs-overload-set`, pre-existing (it fails at
`7b73a385d^` too, as this ticket already recorded) and untouched here.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
