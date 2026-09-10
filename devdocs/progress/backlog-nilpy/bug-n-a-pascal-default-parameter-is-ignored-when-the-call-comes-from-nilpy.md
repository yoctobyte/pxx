---
slug: bug-n-a-pascal-default-parameter-is-ignored-when-the-call-comes-from-nilpy
type: bug
track: N
prio: 55
status: open
owner: frankuser
---

## summary

A Pascal `const x: Variant = 1` default is NOT applied when the call arrives from
NilPy: the omitted argument comes through as `pynone` (`pyvartag` 0,
`pyvar_to_int` 0) instead of the declared default. The same declaration honours
its default correctly when called from Pascal.

## the measurement

`lib/rtl/zlib.pas`, two throwaway probes in the unit's Python surface:

```pascal
function zdbgtag(const value: Variant = 1): Int64; begin Result := pyvartag(value); end;
function zdbgint(const value: Variant = 1): Int64; begin Result := pyvar_to_int(value); end;
```

```
            tag   int
arity 0      0     0     <- declared default is 1; pynone arrived instead
arity 1      1     1     <- explicit 1
```

From Pascal the same function at arity 0 returns the declared default. Compiler
`b092b705aacb`, tree `09976a4e8`+.

## why it is prio 55 and not higher

It is silent, and it is silent in the worst direction: the value a caller gets is
0, which is a *legal* value for most optional numeric arguments. Every shim in
`lib/rtl` that declares a Variant default is exposed, and the failure shows up as
a plausible wrong number rather than an error.

## THE REASON THIS SAT UNSEEN, AND IT IS THE REUSABLE PART

`zlib.crc32`'s CPython default is **0**, which is exactly the value an unsupplied
argument already reads as. All four crc32 rows matched the CPython oracle -- two
of them with the top bit set, and the chunked-continuation row too -- while the
mechanism was completely broken. `zlib.adler32`'s default is **1**, so its `a`
accumulator started at 0 and every row was wrong by a visible amount.

**The expected value collided with the do-nothing value**, which is the class
CLAUDE.md already names ("if the machinery did nothing at all, would this row
still pass?"). A shim whose optional argument defaults to 0, to None, or to
anything falsy cannot test this at all. Pick a probe whose correct answer differs
from the absent-argument answer, or the guard cannot fail.

## repro

```python
import zlib
print(zlib.adler32(b"hello"))        # 103219732 with the bug; CPython 103547413
print(zlib.adler32(b"hello", 1))     # 103547413 -- correct, explicit
```

With the workaround in place (see below) both print 103547413.

## the workaround that is in the tree, and what to delete when this is fixed

`lib/rtl/zlib.pas` keeps the declared default -- that is the correct Pascal
signature -- and adds `ChecksumSeed(value, whenAbsent)`, which tests
`value = pynone` and substitutes CPython's documented start. That is
`mimic_urllib_request.pas`'s established idiom (`isNone := data = pynone` in
`DataToString`), not a new mechanism, and it is harmless once the frontend
honours the declaration: the test simply stops firing. Delete it then, or leave
it; it costs a comparison.

## a second idiom exists and may be the intended one

`mimic_urllib_request.pas` spells `urlretrieve`'s optional argument as TWO
arity-differing `overload`s rather than a default, and `getheader` does the same.
Arity-differing overloads are not hit by
`bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type`, which
is about overloads differing only in argument TYPE. If defaults are not meant to
work across this seam, say so and the shims should stop declaring them --
silently ignoring one is the worst of the three options.
