---
slug: bug-n-a-variant-default-parameter-arrives-as-none-from-nilpy-while-typed-defaults-apply
type: bug
track: N
prio: 55
status: open
owner: frankuser
---

## summary

A **Variant** default parameter is not applied when the call arrives from NilPy:
the omitted argument comes through as `pynone` (`pyvartag` 0, `pyvar_to_int` 0)
instead of the declared default. **Boolean, Integer and AnsiString defaults are
applied correctly**, so the default-value machinery works and only the Variant arm
is wrong. The same Variant declaration honours its default when called from
Pascal.

## RE-TITLED 2026-09-11 — it was filed as "a Pascal default parameter is ignored"

That was too wide and frankB caught it. The wide version tells every shim author
their defaults are unreliable when three of four kinds are fine, and it points a
fixer at the whole default machinery instead of at the one arm that special-cases
Variant. Their probe, independently reproduced here at compiler `b092b705aacb`
(frankB's at `786b88673e62`):

```
b omitted True   | given False      (Boolean = True)      APPLIED
i omitted 7      | given 3          (Integer = 7)         APPLIED
s omitted dflt   | given x          (AnsiString = 'dflt')  APPLIED
v omitted 0      | given 5          (Variant = 1)          NOT APPLIED
vtag omitted 0   | given 1          <- the omitted slot's tag is 0 (none)
```

**Their probe design is the lesson and it is the inverse of my mistake below.**
Every default was chosen so an unapplied default could not produce it by accident:
`Boolean = True` (absent reads False), `Integer = 7`, `AnsiString = 'dflt'`. In
their words: had they written `Boolean = False` they would have reported the same
green I did.

Reaching such a unit from NilPy needs the extension form —
`import 'mimic_dfltchk.pas' as d` — because a bare import resolves to Python only.
The compiler says so itself, and says it well; see the contrast in
[[bug-n-a-bare-nilpy-import-falls-through-to-a-host-c-header-of-the-same-name-and-says-nothing]],
where the same frontend takes a wrong route silently.

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

## the idiom that is already correct, measured by frankB

`mimic_sqlite3`'s `execute(sql; parameters: Variant = 0)` is the affected kind and
is nonetheless safe, because its guard is spelled **positively**:
`pyvar_is_objtag(parameters)`. That answers "no parameters" correctly whether the
omitted slot holds NONE today or an int-tagged 0 after this is fixed. The negative
spelling `not pyvar_is_inttag(...)` would call NONE a sequence and raise TypeError
from inside the shim. So the rule for a shim with a Variant default is: **test for
what you CAN handle, not for what you cannot** — it survives the fix either way.

## a second idiom exists and may be the intended one

`mimic_urllib_request.pas` spells `urlretrieve`'s optional argument as TWO
arity-differing `overload`s rather than a default, and `getheader` does the same.
Arity-differing overloads are not hit by
`bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type`, which
is about overloads differing only in argument TYPE. If defaults are not meant to
work across this seam, say so and the shims should stop declaring them --
silently ignoring one is the worst of the three options.
