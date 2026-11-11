---
slug: bug-n-min-and-max-as-a-value-bind-to-the-two-argument-arm-in-the-wrong-unit
title: min and max as a value bind to the two-argument arm in the wrong unit
summary: >
  `f = min; f([3, 1, 2])` raises `TypeError: expected a number, got object`
  (max: `got int`) where CPython answers 1. The bare name resolves to pylib's
  SCALAR-PAIR arm `min(const a, b: Variant)`, which is then called with one
  argument, so `b` reads whatever the dispatcher left staged. The ITERABLE arm
  that should serve it, `min(const v: Variant; key: Pointer = nil)`, lives in
  pyeval, and PyFindVariantParamOverload is deliberately scoped to the callee's
  OWN unit -- so it can never be reached from a pylib starting point. `min(xs)`
  spelled as a CALL is correct throughout; only the value form is wrong.
track: N
type: bug
prio: 55
owner: unassigned
status: done
---

## Measured

2026-09-13 (frankS), at 34a9a7609 and still at f89a1d2eba30:

    f = min; print(f([3, 1, 2]))   TypeError: expected a number, got object
    f = max; print(f([3, 1, 2]))   TypeError: expected a number, got int
    print(min([3, 1, 2]))          1        correct
    print(max([3, 1, 2]))          3        correct

All three shapes of the value form fail identically -- `f = min; f(xs)`,
`map(min, [[...]])` and `f = min; map(f, [[...]])` -- so it is the binding, not
the call site.

## The mechanism, printed rather than reasoned

A temporary `WriteLn` in PyMakeFuncValueFor's wrapper gate, at the point where
the callee is finally chosen:

    PROBE nm=min pi=1268 pc=2 req=2 ret=22 alt=1268

`pc=2` with `req=2` is the tell: this is NOT one of the `key: Pointer = nil`
arms (those are ParamCount 2, required arity 1). It is
`pylib.pas:2268 function min(const a: Variant; const b: Variant): Variant` --
the two-argument scalar form, whose required arity genuinely IS 2.

`alt=1268` means PyFindVariantParamOverload was asked for an all-Variant
overload of arity 2 and returned the same proc. It could not have done better:
its unit scope is `ProcUnitIdx[i] <> ProcUnitIdx[ofPi] then Continue`, the
starting proc is in **pylib**, and every iterable arm
(`min(l: TPyList; key: Pointer = nil)`, `min(const v: Variant; key: Pointer = nil)`,
the TPyDict/AnsiString/TPyIter/TPyRange rows) is in **pyeval**. The two units
split one Python builtin across an invisible boundary.

The unit scope is not an oversight and must not simply be widened -- its own
comment records two measured silent-wrong-value bugs from a program-wide scan
(`b = twinmod2.parse` answering twinmod's, `zz = casemod.Pick` answering
`pick`'s). Whatever fixes this has to keep that.

## What the fix has to decide

In CPython `min` is ONE function that accepts either an iterable or the values
spread out, and a callable VALUE of it has to serve both:

    f = min; f([3, 1, 2])   -> 1     the iterable form
    f = min; f(3, 1)        -> 1     the scalar form

so binding the bare name to either single arm is wrong for the other. Today it
is bound to the scalar arm and the iterable form is the broken one. Note the
compiler already knows these two spellings coincide for exactly these two names
-- `PyStarIsIterableForm` is a two-entry list of `min`/`max` -- which is the
same fact this needs, in the place a fix could reuse it.

This is the same QUESTION as
[[bug-n-abs-is-not-a-value-while-len-and-str-are]] ("which overload does a bare
builtin name mean as a value?") but a different MECHANISM: there the name has no
proc at all, here it has several and picks the wrong one in the wrong unit. They
want one answer and two patches; do them in one pass.

## Why it is filed rather than fixed

Found while fixing the neighbouring defaulted-tail bug (`f = sorted; f(xs)`
answering `[]` -- that one is fixed, in the same area of
PyMakeFuncValueFor). This one needs a dispatcher that can serve both arities
from one value, or a cross-unit resolution rule that does not reinstate the two
bugs the unit scope exists to prevent. Neither is a change to guess at beside a
different fix.

## Positive control for whoever takes it

`f = min; f(3, 1)` -- the SCALAR form -- IS correct today: measured, not
predicted, `1` and `3` against CPython's `1` and `3`. That is the arm the name
binds to, which is why it works. A fix that makes the iterable form work must
not silently trade it away, and a fixture asserting only the iterable form
cannot see that happen.


## The same question, a much larger population -- measured 2026-09-13 (frankS)

This ticket is filed as two builtin names. It is not two names; it is the
general question **"how many arguments does a callable value pass?"**, and the
second population is every lib/rtl shim with a defaulted tail:

    f = json.dumps; f([1, 2])                  TypeError: expected a number, got int
    f = json.dumps; f([1, 2], -1, True, False) [1, 2]      CORRECT today

    function dumps(const obj: Variant; indent: Integer = -1;
                   ensure_ascii: Boolean = True; sort_keys: Boolean = False): AnsiString;

The wrapper is built at **4**. `PyCallableValueArity` returns
`PyProcRequiredArity` only when the callee's unit is `pylib` or `pyeval`, by NAME,
and `json` is neither -- so the defaulted tail is treated as required. Found while
fixing [[bug-n-a-stdlib-shim-function-returning-a-container-is-broken-when-taken-as-a-value]],
whose return-side and parameter-side gates are now closed; this arity residue is
what is left, and it is here rather than there because it is this ticket's
question.

**Do not fix it by adding `json`, `re`, `mimic_struct`... to that unit list.**
Unit-name scoping is exactly the "name is not the thing" failure this repo keeps
paying for, and here the widened list would ALSO be wrong on the merits: for a
pylib builtin we chose required arity and accepted that `f = sorted; f(xs, key)`
cannot pass the optional argument, but **`json.dumps(obj, indent=2)` is ordinary
Python**, so required arity breaks a real spelling and full arity breaks the
common one. Neither single arity is right, which is the same conclusion the
min/max section above reaches from the other direction.

**The refusal is a MEASUREMENT, not caution, and that is the part to keep.** A
one-line fix was available and working -- add `json` to the unit list -- and it
was declined because the measurement shows **the list was never the mechanism**:
required arity breaks `dumps(obj, indent=2)` and full arity breaks `dumps(obj)`,
so no membership test over units can be right, however the list is spelled. A
widened list would have closed the row and left the defect, which is the shape
that gets a ticket reopened later with the fix already in it.

If a discriminator is needed it should be something the DECLARATION carries --
`ProcParamHasDefault` already does, and `ProcSigOff` marks a NilPy def -- never
where the file sits. The honest shape is a wrapper that forwards a variable
count, or one wrapper per reachable arity, which serves min/max too.

## The free instrument

`procs=N` in the compiler's own `ok:` line counts a synthesized wrapper: the
VALUE spelling reads one higher than the CALL spelling when a wrapper was built
and identical when it was not. `re.findall` 2155 -> 2156 (wrapped),
`json.loads` 2393 -> 2393 (not wrapped, before the fix). No probe, no rebuild --
the temporary `WriteLn` recorded above is not needed to answer this class.

**It is a DIFFERENTIAL reading and it is only sound when the two compiles differ
in one thing.** Anything else that changes between them moves the count too, so
it holds for the call-versus-value spelling of ONE name in ONE file and does NOT
hold across a pull, a rebuild, or two different programs. Read it as a delta
between two invocations you made back to back, never as an absolute.

## Resolution (2026-11-11)

**min / max:** already correct on master when rechecked. `f = min` serves
`f([3, 1, 2])` and `f(3, 1)`, and `map(min, ...)` / `map(max, ...)` agree with
CPython.

**The json.dumps half had got worse:** `f = json.dumps; f([1, 2])` SEGFAULTED.
It now matches CPython for `f(x)`, `f(x, indent=2)`, `f(x, sort_keys=True)`,
`f(x, ensure_ascii=False)` and `map(json.dumps, ...)`. The discriminator is the
declaration, as this ticket asked; no unit list was added.

- `PyCallableValueArity`: a Pascal routine outside pylib/pyeval, i.e. not a
  NilPy def, gets its required arity plus the run of defaulted parameters whose
  Pascal default is *bakeable* (new `PyPascalDefaultIsBakeable`: an ordinal,
  bool or float, or a Variant's zero default, which becomes None). The run stops
  at the first string, set or pointer default, and Pascal fills that one and
  everything after it.
- `PyCopyPascalDefaultsToWrapper` copies those defaults onto the synthesized
  `$pycallwrap_N`. EmitPySignatures bakes them into the wrapper's signature
  record, and the dispatcher fills omitted arguments from it as it does for a
  def.
- The box carries the WRAPPER's signature when the real routine is Pascal and
  the wrapper took defaults. Pascal routines have no record of their own.
  pylib builtins keep their old path (their wrapper takes no defaults).
- The wrapper's parameters take the real routine's names instead of `a0..aN`,
  so keywords through the value match. The body refers to parameters by
  symbol, so nothing else reads the names.

Test `test/test_nilpy_a_shim_function_with_defaults_taken_as_a_value.py`
(row `shimdflt26`). The `abs` half is its own ticket,
[[bug-n-abs-is-not-a-value-while-len-and-str-are]].
