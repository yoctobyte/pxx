---
slug: bug-n-a-shim-parameter-typed-as-a-container-blocks-the-callable-value-wrapper
title: a shim parameter typed as a container blocks the callable-value wrapper
summary: >
  `f = struct.unpack; f("<f", packed)` raises `error: bad char in struct format`
  where `struct.unpack("<f", packed)` is correct in the same program.
  `unpack(const fmt: AnsiString; b: TPyBytes)` has a tyClass PARAMETER, and
  PyScalarWrappableParamType declines it -- correctly, because there is no
  Variant -> TPyBytes call-argument coercion to lower, and a wrapper built over
  one would be a compile error inside a SYNTHESIZED body naming a proc the
  program never wrote. Declining boxes the raw address, so the arguments go
  uncoerced and the callee reads a Variant slot as its format string -- which is
  why the complaint names the FORMAT and not the parameter that caused it. The
  fix is the missing coercion, not a widened predicate.
track: N
type: bug
prio: 35
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
