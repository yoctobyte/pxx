---
slug: bug-n-a-shim-parameter-typed-as-a-container-blocks-the-callable-value-wrapper
title: a shim parameter typed as a container blocks the callable-value wrapper
summary: >
  `f = struct.unpack; f("<f", packed)` raises `error: bad char in struct format`
  where `struct.unpack("<f", packed)` is correct in the same program, because
  PyScalarWrappableParamType declines a tyClass parameter and the declined arm
  boxes the raw address, leaving the arguments uncoerced. THE ORIGINAL DIAGNOSIS
  IN THIS TICKET WAS WRONG and is corrected below: a Variant->TPyBytes coercion
  DOES exist (measured three ways), so nothing is missing. Admitting tyClass is
  a one-line change that makes `f = struct.unpack` work -- and breaks
  test_nilpy_callable_value_defaults and _with_star_args with `expected an
  object argument, got int`, because it changes which OVERLOAD the wrapper is
  built over. The real work is overload selection, not a coercion.
track: N
type: bug
prio: 45
owner: unassigned
status: open
---

## Measured 2026-09-13 (frankS), at the commit fixing the return/parameter gates

    import struct
    p = struct.pack("<f", 1.5)
    print(struct.unpack("<f", p))     (1.5,)                        correct
    f = struct.unpack
    print(f("<f", p))                 error: bad char in struct format

    f = struct.pack;    f("<f", 1.5)  b'\x00\x00\xc0?'              correct
    f = struct.calcsize; f("<3f")     12                            correct
    f = re.findall;     f("a","banana")  ['a','a','a']              correct

So this is not "module members as values are broken" -- it is one parameter
shape. `pack` and `calcsize` take only strings and Variants; `unpack`'s second
parameter is `TPyBytes`.

## Why the predicate is right to decline, and what that leaves

`PyGetOrMakeCallableWrapper` hand-builds `return realproc(a0, a1)` with
`const aN: Variant` parameters, so every parameter is fed by the ORDINARY
call-argument coercion Variant -> that type. For AnsiString, Integer, Boolean,
Double that coercion exists. For a class it does not, and
`PyScalarWrappableParamType`'s own comment says the alternative is a compile
error reported against a proc the program never wrote.

The else arm is not harmless, and that is the part worth ranking: it boxes the
RAW ADDRESS and calls it through the Variant ABI, so the callee reads its
parameters out of whatever the dispatcher staged. The error therefore names the
FORMAT STRING -- the first parameter, which was fine -- for a defect caused by
the second.
[[bug-n-a-stdlib-shim-function-returning-a-container-is-broken-when-taken-as-a-value]]
is the same misdirection on the return side and records the general shape.

## What a fix has to supply

A Variant -> TPyBytes / TPyList call-argument coercion, i.e. unboxing an object
already carried in a Variant. The value IS an object pointer in the Variant, so
this is likely a tag check and a cast rather than a conversion -- but it has not
been measured, and the wrapper is the wrong place to discover that it is not.

Not to be fixed by widening `PyScalarWrappableParamType`: without the coercion
the wrapper does not compile, and the failure would surface as a compile error
in synthesized source.

## Positive control for whoever takes it

`f = struct.pack; f("<f", 1.5)` and `f = struct.calcsize; f("<3f")` must keep
working -- they are the same module through the same door, and they are what
proves a fix widened the parameter set rather than disabling the value path for
shims. `test_nilpy_a_shim_returning_a_container_as_a_value.npy` already carries
calcsize and would catch that.


## CORRECTION 2026-09-13 (frankS) -- this ticket was filed on a false premise

I wrote that the obstacle is a missing `Variant -> TPyBytes` call-argument
coercion, and that "without the coercion the wrapper does not compile". **Both
are false, and I measured them rather than reasoning about them only after a
peer's unrelated question sent me back to the probe.** The coercion exists.
Three spellings, all answering `(1.5,)` against CPython, the middle one carrying
the bytes through a Variant because an unannotated parameter IS one:

    struct.unpack("<f", b)                         direct, static TPyBytes   ok
    def go(fmt, v):        struct.unpack(fmt, v)   UNANNOTATED -> Variant    ok
    def go(fmt, v: bytes): struct.unpack(fmt, v)   annotated                 ok

## What the obstacle actually is -- measured by applying the fix

Widening the predicate by one term:

    Result := (tk = tyVariant) or (tk = tyClass) or PyScalarWrappableRetType(tk);

builds green, and `f = struct.unpack; f("<f", b)` then answers `(1.5,)` twice,
matching CPython. It also **breaks two fixtures**:

    test_nilpy_callable_value_defaults            TypeError: expected an object argument, got int
    test_nilpy_callable_value_defaults_with_star_args   same

So the wrapper does compile, and the failure is not in a synthesized body. What
the widening actually changes is **which overload the wrapper is built over**:
admit a class parameter and an arm taking one becomes eligible where a scalar
arm was picked before, so an `int` from the call site lands in a class slot. The
coercion works for a Variant that HOLDS an object and nothing checks that it
does.

Reverted rather than landed -- it is a real fix for one row and a real
regression for two, which is not a trade to make quietly.

## What a fix has to decide, restated

Not "add the coercion". Either:

- pick the overload BEFORE deciding wrappability, so the parameter kinds under
  test are the ones the call will actually use; or
- admit a tyClass parameter only where the argument is statically known to be an
  object, which pushes the decision back to the call site; or
- make the mismatch a run-time check with a real diagnostic instead of
  `expected an object argument, got int` from inside a synthesized proc.

## Positive control for whoever takes it -- now a measured one

`test_nilpy_callable_value_defaults` and
`test_nilpy_callable_value_defaults_with_star_args` MUST stay green: they are
the two the obvious one-liner breaks, they were found by running them and not by
predicting them, and a fixture asserting only `struct.unpack` would certify the
regression. `f = struct.pack; f("<f", 1.5)` and `f = struct.calcsize; f("<3f")`
must also keep working -- same module, same door.
