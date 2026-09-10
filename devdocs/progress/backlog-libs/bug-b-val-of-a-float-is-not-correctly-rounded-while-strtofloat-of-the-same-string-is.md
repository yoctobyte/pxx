---
slug: bug-b-val-of-a-float-is-not-correctly-rounded-while-strtofloat-of-the-same-string-is
track: B
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [rtl, builtin, float, parsing, two-mechanisms-one-concept]
blocked-by: []
summary: "IT CORRUPTS OTHER PEOPLE'S MEASUREMENTS BEFORE ANYONE NOTICES IT AS A PARSER DEFECT, and that is the argument for its priority rather than the count: a 6000-pair ArcTan2 differential reported 2569 of 6000 ArcTan values disagreeing with glibc, against a file header that says ArcTan is exact, and the harness was the wrong thing -- it had `Val`'d the decimals into different doubles than CPython did. `Val(s, d, code)` for a Double parses 1574 of 6000 ordinary 17-digit decimals to the WRONG double, while `StrToFloat` parses the same 6000 strings correctly. Two parsers for one concept: sysutils' ParseFloatCore is correctly rounded; `ValFloat` in compiler/builtin/builtin.pas accumulates `mant*10+d` and then divides by a power of ten, so every digit rounds and the error compounds. `Val` is not a niche entry point -- `Read`/`ReadLn` of a float lowers to ValFloat (pasparser_stmt.inc:4239 and :8343) and PXXVarNumCoerce's string-to-number ladder calls it, so a program that reads a float from a file gets a value that is not the nearest double to what the file said. The obvious remedy does NOT apply: builtin.pas is a BUILTIN unit and cannot reach sysutils, which is the same wall math.log hit."
---

# Measured 2026-09-10, compiler `pascal26` at HEAD

## Read this part first: it found ME, not the other way round

A 6000-pair `ArcTan2` differential
([[bug-b-arctan-answers-nan-above-1e300-which-is-why-math-atan2-is-still-refused]])
came back with **2569 of 6000 `ArcTan` values disagreeing with glibc**, against
a file header that says `ArcTan` is exact and a landed test that asserts it on
the bits. Every instinct said the RTL had a second defect. The disagreement was
the harness: the Pascal side had `Val`'d its decimal arguments into different
doubles than CPython had. Feeding the same sweep as raw hex bits, with a
round-trip precondition asserted and BRANCHED on, brought it to 0 of 6000.

**A parser that silently returns a nearby double is an instrument that lies by
being correct about something else** — it does not error, it answers, and what
it answers about is a number nobody asked for. Every float differential in this
tree that reads its inputs as text is exposed to it, and the failure looks like
a defect in whatever was being measured. That is a better argument for
priority than the raw count below.

## The contrast, which is the whole finding

6000 decimal strings, `repr()`-form doubles from a uniform spread of exponents
in [-320, 308], parsed three ways and compared as raw IEEE bits against
CPython's `float()`:

| parser | wrong |
| --- | --- |
| the COMPILER's float literal parser (`x := 1.7e-199;`) | **0 / 200** |
| `StrToFloat(s)` — sysutils `ParseFloatCore` | **0 / 6000** |
| `Val(s, d, code)` — builtin `ValFloat` | **1574 / 6000** |

Same strings, same program, same run. The compiler's own literal parse and
sysutils' runtime parse are both correctly rounded; the third one is not.

Examples (string, what `Val` returns, the nearest double):

```
-1.701032016227767e-199   96AA0A86A0580940   96AA0A86A0580942
 2.5713535225823995e-305  00B20E812BD140EA   00B20E812BD140E8
-9.018397582190982e+209   EB85F2020791FB9E   EB85F2020791FB9C
 6.513497922964598e+242   72586BB1B2AEB135   72586BB1B2AEB138
```

## The mechanism

`compiler/builtin/builtin.pas:2211`, `ValFloat`:

```pascal
  mant := mant * 10.0 + (Ord(s[i]) - Ord('0'));   { rounds, per digit }
  ...
  mant := mant / scale;                            { rounds }
  while expval > 0 do
    if eneg then mant := mant / 10.0 else mant := mant * 10.0;   { rounds, per decade }
```

Seventeen significant digits is seventeen roundings before the exponent is even
applied, and a 300-decade exponent is 300 more. Nothing here is a bug in any one
line; the algorithm simply is not a correctly-rounded decimal-to-binary
conversion. `ParseFloatCore` in `lib/rtl/sysutils.pas` is one.

## Why the one-line fix is not available

`compiler/builtin/builtin.pas` is a BUILTIN unit. It cannot `uses sysutils` —
the same wall `math.log` and `math.dist` hit
([[bug-n-math-trunc-and-log-need-frontend-intercepts]]), and the reason
`ValFloat` was hand-rolled "pure float arithmetic — no libc" in the first place.
So the work is one of:

1. move the correctly-rounded core into a place both can reach, and let
   `ParseFloatCore` and `ValFloat` become two callers of one routine — the
   [[normalise-dont-special-case]] answer, and the one that stops this from
   happening a third time; or
2. port the correctly-rounded algorithm INTO builtin.pas, which leaves two
   implementations of one concept and is how this ticket exists.

Prefer 1. This is a textbook instance of the rule: of two paths for one
concept, the one nobody extended is the one that stayed broken.

## `-dPXX_FLOAT_EXACT` is not a workaround

**It does not change this.** That flag selects math.pas's
double-double transcendental kernels; it has nothing to do with parsing, and
the 1574 is identical with and without it. Anyone reaching for it as a
workaround will measure no change.

## A guard a fix must carry

A round-trip assertion over a spread that includes subnormals and the extremes,
compared on the BITS: `Val(repr(d)) = d` for every double in the sample. A
printed comparison cannot see this — the values differ in the last place or
two, and our own float formatter prints the shortest round-tripping decimal,
which will print the WRONG double's shortest form perfectly happily.
