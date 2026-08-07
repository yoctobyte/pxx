---
track: N
prio: 45
type: bug
summary: "NilPy: a lambda called with the wrong number of arguments does not raise — `f = lambda x: x` answers 1 for f(1, 2) and None for f(), where CPython raises TypeError. A def with the same signature is correctly diagnosed at compile time"
status: done
owner: claude-AN
---

# A lambda call with the wrong argument count does not raise

- **Type:** bug (missing diagnostic) — **Track N**
- **Found:** 2026-08-07, split out of
  [[bug-nilpy-a-lambda-call-is-not-arity-checked]] once that ticket's silent
  wrong value was fixed.

## Measured (self-hosted fixedpoint at `db43ea06d` + the defaults fix)

```python
f = lambda x: x
print(f(1, 2))     # CPython: TypeError    pxx: 1     (extra arg dropped)
print(f())         # CPython: TypeError    pxx: None  (missing arg reads None)
```

A `def` with the same signature is correctly rejected at **compile** time
(*"candidates: g(Variant)"*), so this gap is specific to the lambda/callable
value path, where the callee is only known at run time.

Now that a defaulted parameter is a real parameter, the legitimate arity of a
lambda is a **range**: `lambda x, y=k:` accepts one or two arguments. Any check
has to honour that range, not a single count.

## Where the check would go, and why it did not land with the defaults fix

The call is fully dynamic — `pyvar_callv<n>(callee, args…)` in `pyeval.pas` —
so this is a run-time check, not a compile-time one. `pyvar_callv<n>` is the
dispatcher for a **user-written call**, which is exactly the right place: the
callback bridges (`pyboundfn_callv`, which always passes `nargs=1`) go straight
to `pyboundfn_callvn` and would stay lenient, as they must.

The information is nearly all there already: a bound-fn object carries `NOwn`
and now `NDefBase`/`NDef`, so the accepted range is `NDefBase …
NDefBase + NDef`. Two things are missing:

1. **An "arity is known" marker.** `NDefBase`/`NDef` are only set by the lambda
   lifter. A nested-def bound-fn leaves them at 0, which must not be read as
   "takes zero arguments". A sentinel (`NDefBase = -1` = unchecked) keeps every
   non-lambda builder lenient.
2. **The same for the pyeval-closure path.** `Closures[].Params` now lists the
   defaulted names, but a closure built for a nested *def* binds its defaults as
   caps and excludes them from `Params`, so a param count read off `Params`
   would under-count and reject a legal call. That path needs its own required/
   total pair before it can be checked.

## The risk that has to be measured first

A GUI callback is the hazard, and it cuts both ways. Tk calls a `command=`
handler with 0 arguments and a `bind()` handler with 1. Today a mismatch is
silently tolerated; with a check it would raise. CPython raises too, so matching
it is *correct* — but if any `examples/**` app currently relies on the leniency,
this turns a working demo into a crash.

**Do not land this without first checking whether the tkinter facade's callback
invocations reach `pyvar_callv<n>` or go straight to the bridge.** If they reach
the dispatcher, the check needs to exempt them explicitly. That question was not
answered when this was split out — the GUI demos need a display to exercise, and
guessing was the wrong call for a diagnostic that can only ever turn working
code into raising code.

## Gate

Per-fix loop. A `.npy` test covering: too many arguments, too few, a defaulted
parameter called at both ends of its legal range (must NOT raise), a
zero-parameter lambda called with none, and a `def` with the same signatures —
diffed against CPython with `tools/pydiff.py`. Plus whatever the tkinter
question above turns up.

## 2026-08-07 — the blocking tkinter question, ANSWERED: the GUI path is not affected

The ticket said not to land without checking whether the tkinter facade's
callback invocations reach `pyvar_callv<n>`. **They do not**, and the trace is
short enough to state in full:

`lib/pcl/tkinter.pas:TkiCallValue` → `pycall_value` (pyeval) → one of
`pycallback_call0/1`, `pyclosure_call_ptr`, `pyboundfn_call_ptr`, or a direct
call through the raw code address. `pycall_value` never calls `pyvar_callv<n>`.

So the callback bridges keep their leniency by construction and need **no
explicit exemption** — a `command=` handler taking 0 arguments and a `bind()`
handler taking 1 both go down a path the check cannot see. No `examples/**` app
can be turned into a crash by this.

## FIXED — an explicit range on the closure row, not a count derived from Params

The headline repro turned out to use the **pyeval-closure** path, not the
bound-fn path: a capture-free `lambda x: x` lowers to
`pyclosure_src_new(params, src)` (confirmed with `PXXDBG=a.ir`). So the
bound-fn half the ticket sketched would not have moved this repro at all.

- `TPyClosure` gains `ReqN`/`TotN`, defaulting to **-1 = unchecked**.
- New chained builder `pyclosure_setarity(obj, req, tot)`, emitted **only** by
  the lambda lowering (`PyParseLambdaStub`), with `req` = the plain parameter
  count and `tot` = that plus the defaulted ones.
- `pyvar_callv0..3` — the four USER-call dispatchers, and only those — refuse a
  count outside the declared range with a `TypeError`.

Recorded at build time rather than counted from `Params` at run time because
the two disagree, which is the trap the ticket flagged: a closure built for a
nested **def** binds its defaults as captures and leaves them out of `Params`,
so a count read off `Params` under-counts and would reject a legal call. Any
builder that does not call `pyclosure_setarity` stays unchecked forever, so the
check can only ever fire on a shape that explicitly declared its arity.

### Measured

`(lambda x: x)(1, 2)` now raises
`TypeError: <lambda>() takes 1 positional argument but 2 were given` — the same
text CPython prints. `f()` raises likewise.

Test `test/test_nilpy_lambda_arity.npy`, **13 lines byte-identical to the
CPython oracle**, catching each error so the whole matrix is one stdout
comparison: too many, too few, both ends of a defaulted range (must NOT raise),
a zero-parameter lambda with and without an argument, a two-parameter lambda
(so the count is the lambda's own and not a fixed 1), a lambda called through a
function parameter, and a nested def that must stay lenient.

### Noted in passing, already filed elsewhere

`lambda x, y=10:` — a LITERAL default — is refused at compile time
(*"a lambda default capture must be a plain name"*); only `y=name` works.
CPython accepts both. That is a separate syntax gap and is already covered by
`feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep`.

### Not done

The **bound-fn** path (a lambda WITH captures, and lifted lambdas generally)
still has no range. It needs the `NDefBase = -1` sentinel the ticket describes,
because `NDefBase`/`NDef` default to 0 and 0 is also a legal base. Left for a
follow-up rather than guessed at: the closure path is what the repro and the
`.npy` suite exercise, and adding an unexercised second checker to a diagnostic
that can only turn working code into raising code is the wrong trade.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`.

## Log
- 2026-08-07 — resolved, commit 863fd9161.
