---
slug: bug-n-a-stdlib-shim-function-returning-a-container-is-broken-when-taken-as-a-value
title: a stdlib shim function returning a container is broken when taken as a value
summary: >
  FIXED for the RETURN and PARAMETER halves. `f = re.findall; f("a", "banana")`
  SEGFAULTED where the call spelling was correct in the same program, and
  `f = json.loads` reported about the JSON TEXT; both now match CPython. The
  wrapper gate knew two reasons to adapt a callable value (ARITY, RETURN) and
  needed three: a tyClass result is now admitted for the SYNTHESIZED wrapper
  (whose body is always `return realproc(a0, ...)`, so freshness is the lambda
  path's question and not this one), and a non-Variant PARAMETER is now a reason
  to wrap on its own. Declining had never meant "no wrapper" -- it boxed the RAW
  ADDRESS, so the ARGUMENTS went uncoerced too, which is why every symptom named
  the argument. STILL OPEN, two residues with separate causes, both filed:
  `json.dumps` (wrapper built at the wrong ARITY -- PyCallableValueArity is
  scoped by UNIT NAME, so a lib/rtl shim gets full ParamCount) and
  `struct.unpack` (a tyClass PARAMETER has no Variant coercion).
track: N
type: bug
prio: 70
owner: frankS
status: done
---

## Measured 2026-09-13 (frankS), at 9fb9634c4 + pin v409

Each row is one program; the CALL spelling and the VALUE spelling of the same
function, so the comparison is inside one compilation:

    import re
    print(re.findall("a", "banana"))     ['a', 'a', 'a']     correct
    f = re.findall
    print(f("a", "banana"))              SIGSEGV

With a single call it does not crash -- it prints an EMPTY LINE and exits 0,
which is the silent-wrong-value shape. The crash needs a second use.

    f = json.loads;      f("[1, 2]")        EJSONError: JSON: unexpected ...
    f = json.dumps;      f([1, 2])          TypeError: expected a number ...
    f = struct.unpack;   f("<f", packed)    error: bad char in struct format
    f = struct.calcsize; f("<3f")           12    CORRECT -- returns Integer

## The discriminator is the RETURN type, and the symptom is in the ARGUMENTS

`PyMakeFuncValueFor` builds a return-adapting wrapper only when the result is
admissible: the scalar/string family, tyVariant, or a tyClass that
`PyProcIsFreshContainerCtor` vouches is freshly constructed. That predicate is
scoped to `pylib` and `pyeval` by unit name, so a `mimic_*` shim returning
TPyList or TPyBytes is declined.

The declined branch is NOT "no wrapper, same as before" in any harmless sense --
it is the pre-existing escape hatch where **the raw code address is boxed and
called through the Variant ABI**. The callee then reads its parameters out of
whatever the dispatcher staged. `struct.unpack(const fmt: AnsiString; ...)` reads
a Variant slot as an AnsiString, which is why the error is about the FORMAT
STRING and names nothing about the return type that actually gated it.

That escape hatch has a history: the same branch produced
`f = string.capwords; f("a b")` printing an empty line and `f = struct.calcsize`
raising `bad char in struct format`, recorded in PyMakeFuncValueFor's own
comment, whose author called it "possibly-unsafe" and left it. This ticket is
the rest of that population.

## NOT a {$PYSTAR} bug -- ruled out, because it looks exactly like one

`struct.pack` was where this was found, and `pack` is the flagship `{$PYSTAR}`
shim, so the obvious reading is that the star collector is not reaching the
value door. It is not that. The 2x2 that rules it out:

    struct.pack("<f", 1.0)            direct call, star        ok
    f = struct.calcsize; f("<3f")     value, no star           ok
    def c(*a); f = c; f(1,2,3)        value, NilPy star        ok
    f = struct.pack; f("<f", 1.0)     value, PASCAL star       BROKEN

and then `struct.unpack` and `re.findall`, which carry NO marker at all, break
identically. A first attempt at this routed `PyMakeFuncValueFor` through
`PyPascalStarIdx` (the lazy accessor) instead of the raw `ProcPyStarIdx` array,
on the theory that the marker was unresolved at value time -- it built, it was
plausible, and it changed NOTHING. Reverted rather than landed. Recorded because
the star reading is what anyone will try first.

(Separately and still true: `PyMakeFuncValueFor` reads the raw `ProcPyStarIdx`
array where a Pascal `{$PYSTAR}` proc's slot is only populated lazily by
`PyPascalStarIdx`. That may be a latent bug. It is NOT this one, and no probe
here demonstrates it, so it is written down rather than fixed.)

## The fork, which is why this is filed and not fixed

Two directions, and they differ in what we are willing to break:

1. **Vouch for more units.** Extend `PyProcIsFreshContainerCtor` so mimic shims
   returning fresh containers get a wrapper. Correct where the callee really
   does construct, and the predicate's own comment insists each body be READ
   rather than inferred -- for good reason: `pydivmod_v` looks like a fresh ctor
   and has a second exit returning the program's own `__divmod__` result, which
   may alias. Per-function reading, per-function risk.
2. **Refuse loudly instead of boxing the raw address.** Strictly better than a
   segfault and honest about what is unsupported. The cost is unknown: some
   callable values presumably work TODAY through the unwrapped path by accident
   of their signature, and this would turn those into compile errors. **Nobody
   has measured that population**, and that census is the thing that makes this
   decidable.

Do the census before choosing. The question it answers: of the callable values
that currently take the unwrapped branch, how many produce a CORRECT result?

## Positive control for whoever takes it

`struct.calcsize` as a value must keep working -- it returns Integer, gets a
wrapper today, and is the row that proves a fix did not simply disable the
value path for module members. And the fixture must call the value TWICE:
`re.findall` prints an empty line on one use and only segfaults on the second,
so a single-call fixture sees the silent arm and can be read as a lesser bug
than it is.

## Resolved 2026-09-13 (frankS)

Two gates, both in `PyMakeFuncValueFor`, and neither was the fork the ticket
above proposed. The census in option 2 was never needed, because the answer was
not "vouch for more units" OR "refuse loudly" -- it was that the predicate being
consulted was answering a question about a different construct.

### 1. The RETURN gate asked the LAMBDA question of a WRAPPER

`PyProcIsFreshContainerCtor` exists so a lifted LAMBDA does not hand back a
second owner of a captured alias. A lambda body is arbitrary source, so that is
the right question there. A callable-value wrapper's body is always
`return realproc(a0, ...)` -- it returns exactly what a direct call at that site
returns, and boxing an aliasing result is already what the direct call does.
Measured: `x = log.append(i)` 500 times is correct today and matches CPython.
So the wrapper doing the same is not a new ownership claim, and the class arm is
now admitted unconditionally at this site. `PyProcIsFreshContainerCtor` is
UNCHANGED and the lambda path still consults it.

That needed a second, paired change: `PyCompileLambdaBody` discarded a
class-typed result that was not an owned temp, so admitting the wrapper alone
made `f = re.findall; f("a", "banana")` print `None` instead of segfaulting --
the same bug one layer along. `bStart = -1` (the synthesized-wrapper marker) is
now exempt from that discard, and ONLY it. **Both halves are required and either
one alone is a different wrong answer**; that was frankuser's falsification test
and this is its result.

### 2. The gate knew two reasons to wrap and there were three

The comment enumerated ARITY and RETURN. `json.loads(const s: AnsiString):
Variant` needs neither -- Variant return, no defaulted tail -- and still needs a
wrapper, because the dispatcher stages a Variant and the callee reads an
AnsiString. `PyProcNeedsArgAdaptation` is the third disjunct.

### Verified

`test_nilpy_a_shim_returning_a_container_as_a_value.npy`, wired into the
Makefile. It calls each value TWICE, because one use printed an empty line and
exited 0 and only the second crashed. Positive control `struct.calcsize`
(Integer return, worked before). **Negative control: the fixture SEGFAULTS under
pin v409 (rc=139) and matches CPython byte-for-byte at this change** -- run in
place, so it is a control on the shipped compiler and not on a rebuild of mine.
24 named callable-value neighbours re-run green; `tools/gate.sh quick` GREEN.

### Still broken, and they are NOT this bug -- two causes, two tickets

    f = json.dumps;    f([1, 2])           TypeError: expected a number, got int
    f = struct.unpack; f("<f", packed)     error: bad char in struct format

`json.dumps` is an ARITY bug and the mechanism is measured: the wrapper is built
at **4**, because `PyCallableValueArity` decides required-versus-full arity by
UNIT NAME (`pylib`/`pyeval`), and `json` is neither -- so a shim with a defaulted
tail gets full ParamCount. The proof is that the arity-4 spelling
`f([1, 2], -1, True, False)` returns `[1, 2]` correctly today. Same root as
[[bug-n-min-and-max-as-a-value-bind-to-the-two-argument-arm-in-the-wrong-unit]].
Widening the unit list is NOT the fix and the reason is worth keeping: for a
pylib builtin we chose required arity and accepted that `f = sorted; f(xs, key)`
cannot pass the optional argument, but `json.dumps(obj, indent=2)` is ordinary
Python, so neither single arity is right. It wants a wrapper that forwards a
variable count, or one per arity.

`struct.unpack(const fmt: AnsiString; b: TPyBytes)` is the PARAMETER twin of the
return-side fix: `PyScalarWrappableParamType` declines a tyClass slot because
there is no Variant coercion for it, and a wrapper built over one would be a
compile error inside a synthesized body naming a proc the program never wrote.
That is a real obstacle and not a scoping accident -- it needs the coercion to
exist, not a widened predicate.

### The instrument, so nobody rebuilds it

**`procs=N` in the compiler's own ok: line is a free wrapper detector.** A
synthesized wrapper is a proc, so the VALUE spelling of a function reads one
higher than the CALL spelling when a wrapper was built and identical when it was
not. That is what separated `re.findall` (2155 -> 2156, wrapped) from
`json.loads` (2393 -> 2393, not wrapped) and turned a guess about class
parameters into the arity/parameter split above. No probe, no rebuild.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 017dfed7d.
