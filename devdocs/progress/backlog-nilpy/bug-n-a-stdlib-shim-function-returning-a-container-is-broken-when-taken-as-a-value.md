---
slug: bug-n-a-stdlib-shim-function-returning-a-container-is-broken-when-taken-as-a-value
title: a stdlib shim function returning a container is broken when taken as a value
summary: >
  `f = re.findall; f("a", "banana")` SEGFAULTS where the call spelling
  `re.findall("a", "banana")` is correct in the same program. Same for
  `json.loads`, `json.dumps` and `struct.unpack`; `struct.calcsize` is fine. The
  discriminator is the RETURN TYPE: a shim returning a CLASS (TPyList, TPyBytes)
  gets no callable-value wrapper, because the wrapper gate admits a tyClass
  result only when PyProcIsFreshContainerCtor vouches for it and that predicate
  knows only pylib/pyeval. With no wrapper the RAW ADDRESS is boxed and called
  through the Variant ABI, so the ARGUMENTS are never coerced either -- which is
  why it surfaces as `bad char in struct format` rather than as anything about
  the result. Not a {$PYSTAR} bug: `unpack` and `findall` carry no marker.
track: N
type: bug
prio: 60
owner: unassigned
status: open
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
