---
slug: bug-n-a-callee-declared-below-its-caller-gets-the-argument-by-the-wrong-abi
title: a callee declared below its caller gets a container argument by the wrong ABI
summary: >
  FIXED 2026-09-13. An unannotated NilPy parameter is a variant and travels
  const-by-REF, so the caller boxes a non-variant argument into a hidden temp and
  passes its ADDRESS. That decision reads Procs[cpi].Params[k].IsRef, and IsRef
  was written only while the CALLEE'S BODY was parsed -- so every call site
  lowered earlier in the file passed the object handle by value and the callee
  dereferenced it, answering
  "TypeError: expected a str, a list or a dict, got int". The ABI is a property
  of the SIGNATURE, so it is now recorded when the signature is registered.
  This was the live lekkerzeilen wall: gauges.Live.start calls
  `self._apply(held.values())` with `_apply` written below it.
track: N
type: bug
prio: 80
owner: frank-user
status: done
---

## How it was found

The owner ran the compiled demo and reported:

    A game controller, if one is plugged in: left stick steers, ...
    Unhandled exception: TypeError: expected a str, a list or a dict, got int

It is new only in the sense that it needed a SESSION FILE to be reached:
`~/.local/state/lekkerzeilen/session.conf` exists once you have sailed, which
makes `App.__init__` build the gauges, which runs `Live.start()` for the first
time. The CPython twin of the same file runs to completion, so CPython is the
oracle throughout.

Marker instrumentation (a `print("G<lineno>")` before every statement of
`app.py` and `gauges.py`, rebuilt and run) put it at `gauges.py:464` --
`Live._apply`, first statement, `readings = list(readings)` -- reached from
`self._apply(held.values())` on line 428.

## The reduction, and the discriminator is DECLARATION ORDER

    def caller(d):  return callee(list(d))
    def callee(r):  return len(list(r))      # BELOW its caller -> TypeError

Swap the two definitions and it prints the right answer. Twelve spellings were
run as a factorial (callee first/last x argument `list(self.d)` / `held.values()`
/ `self.d.values()` x callee body inline / reassigned): **all six callee-last
rows fail identically and the callee-first rows differ only in a separate,
unrelated defect.** A local variable argument, a `self.d` attribute argument and
an INT-returning call argument are all fine in either order -- it takes a
CONTAINER value reaching a variant parameter.

## The mechanism, measured rather than reasoned

A probe in `IRLowerCallArg` printing the callee's parameter row at lowering time,
one line per argument, is the whole finding:

    callee LAST   ARGPROBE cpi=2055 ... ptk=22 isref=FALSE name=take
    callee FIRST  ARGPROBE cpi=2054 ... ptk=22 isref=TRUE  name=take

One proc, same declared type (22 = tyVariant), `IsRef` different. The boxing arm
in `IRLowerCallArg` that allocates a hidden variant temp and passes `IR_LEA` of
it is reached either way, but the CALLEE's frame treats a variant parameter as
by-reference -- so with IsRef False the caller and the callee disagree about
whether the slot holds the value or its address, and the callee dereferences an
object handle. Read back as a variant, the handle's low half is the tag: `int`.

A second probe, printing every proc after `PyRegisterDefShells` registered it,
showed `p0ref=FALSE scopebase=0` for BOTH orders -- so the shell pass never set
it, and the only thing that did was `PyParseDef` (and `PyParseMethod`) parsing
the body:

    Procs[procIdx].Params[i].IsRef := capByRef;      { pyparser.inc, PyParseDef }

## The fix

`PyMarkVariantParamsByRef(procIdx)` -- set `IsRef` and `ProcParamIsConst` for
every tyVariant parameter at REGISTRATION time -- called from
`PyApplyDefSignature` (which covers module defs, nested defs and the shell pass)
and from the method registration in `PyRegisterClassMembers`.

**Pascal is deliberately untouched, and that is why this is not in
`RegisterProc`.** There `IsRef` is NOT a function of the type: `const v: Variant`
is by-ref and a plain by-value `v: Variant` copies
(bug-pascal-byvalue-variant-param), and pylib's own units go through
`RegisterProc` during a NilPy build.

## Resolution

Fixed, commit b48c40d28 on origin/master (both bugs landed together; the close
is the same commit).

## Verified

- `test/test_nilpy_a_callee_declared_below_its_caller.npy`, 7 rows, `.expected`
  from CPython, MATCH at HEAD. Each row prints a different number so a diff names
  the row.
- Control: under pin v408 rows A, B, C, E and F raise and **D and G pass** -- D
  calls the callee from below it, G declares the callee first. Both are the
  arrangement an ordinary test author writes, and both certify the bug. Taken
  from a try/except variant of the same file, because the plain fixture dies at
  row A and stops.
- `tools/gate.sh quick` and the full `make test-nilpy`.

## The test-design note, and it is the fourth instance

CLAUDE.md's 2026-09-11 rule -- *where a construct takes an ordered list, put the
interesting element LAST* -- is stated about elements within a construct. This is
the same failure one level up: the ordered list is the FILE, and the interesting
element is the callee's definition. Every existing NilPy fixture that calls a
helper declares the helper first, because that is how people write Python, so the
whole suite was drawn from the passing arrangement.
