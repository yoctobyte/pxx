---
track: A
prio: 65
type: bug
summary: "A float LITERAL is up to 1 ULP away from the nearest double — `1e-292` in source is not the same number as `float(\"1e-292\")` in the same program. 23 of 490 sampled literals are wrong. Affects every frontend"
status: done
owner: claude-AN
---

# The float-literal lexer is not correctly rounded

- **Type:** bug (shared lexer — SILENT wrong value, every frontend) — **Track A**
- **Found:** 2026-08-03, by a 500-value differential sweep run to validate the
  new NilPy float formatter
  ([[bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip]]). The sweep
  disagreed with CPython on 23 values; the formatter turned out to be right and
  the literals wrong.

## Repro — one program disagrees with itself

```python
print(1e-292)                       # CPython 1e-292   pxx 9.999999999999999e-293
print(float("1e-292"))              # 1e-292                     — correct
print(float("1e-292") == 1e-292)    # CPython True     pxx False
```

The string parser (`pyfloat_parse` → the correctly-rounded `PyStrToFloatDef`)
and the LEXER, handed the identical text, produce different doubles. Since the
string parser is correctly rounded by construction and verified against CPython,
the lexer is the one that is off — by one ULP.

## Scale — measured, not estimated

A sweep of 400 random 64-bit patterns (printed with CPython's `repr`, so each
text names a specific double exactly) plus a `1e-320 .. 1e308` ladder, run as
`float("<text>") != <the same text as a literal>` inside ONE pxx program:

```
lexer mismatches: 23        (out of 490)
```

Both the random values and the round decades are hit — `1e-292`, `1e-285`,
`1e-229`, `1e-222`, `1e-215`, `1e-208`, `9.87654321e135`, `9.87654321e-236`,
`7.008480465119292e+242`, `-3.799606243167532e-86`, … Every failure is a
denormal-free, ordinary magnitude; nothing about the sample is adversarial.

## Where

`compiler/lexer.inc`, `StrToDoubleBits` — ~179 lines, its own pure-integer
decimal→double conversion, and the THIRD such parser in the tree. The other two
are `lib/rtl/sysutils.pas`'s `StrToFloatDef` (correctly rounded, exact
reconstruction with a Clinger fast path) and its renamed copy in
`compiler/builtin/pylib.pas`. Its own comment claims limitations; those had not
been reproduced before, which is why the decision on the float-core ticket
explicitly declined to sweep it along without a measurement. This is that
measurement.

## Why it matters

The literal you wrote is not the number you get, in any language pxx compiles —
Pascal, C, NilPy, Rust, Zig alike, since they share the lexer. Nothing warns,
and the error is one ULP, so it survives every comparison a program is likely to
make against a nearby value and only shows up in a round trip, a bit pattern, or
an accumulated sum. It also means a `.expected` file containing a float literal
may be recording the wrong number.

Note the cross-check that made this visible is only possible NOW: before
`float(str)` was correctly rounded, both parsers were wrong and the program
agreed with itself.

## Fix shape

The correct algorithm already exists twice in the tree and is proven. The
question is whether the lexer can reach it (it is compiler-internal, so it can
carry its own copy or be rewritten against the same exact-reconstruction
method) — see [[decide-builtin-and-library-code-sharing]] for the general
version of the same layering question. A Clinger fast path covers the
overwhelming majority of literals with a single exactly-rounded multiply, so the
exact path is only entered rarely.

## Gate

A Pascal test and a `.npy` test over the same sweep table: every literal must
satisfy `<literal> == <parser>("<the same text>")`, plus the round decades
`1e-320 .. 1e308`, subnormals, `DBL_MAX`, and the values listed above by name.
Cross targets too — the conversion happens at compile time, so a wrong literal
is baked into every backend's output identically, but the test should prove that
rather than assume it.

## Resolved 2026-08-03

`compiler/exdec.inc` — the exact-decimal core of `lib/rtl/sysutils.pas`, copied,
included from `compiler.pas` ahead of every lexer. `StrToDoubleBits` is now four
lines over `ExDecStrToDouble`. The old rational scaler is deleted; git holds it.

Two edits inside the copy, both forced and both noted in the file: the
`StrToFloatDef` name is `ExDecStrToDouble` (the FPC-seeded bootstrap has real
SysUtils in scope), and `IntToStr` becomes a local helper (the compiler's own
RTL has none — pylib's copy substitutes `StrInt` for the same reason). Copying
rather than reimplementing follows the ruling already made for the pylib copy in
[[decide-nilpy-where-the-exact-decimal-float-core-lives]]; the same constraint
applies verbatim here, since the compiler must not drag `lib/rtl` into its own
build either.

### It also removed a build-path divergence nobody had named

The FPC path used `Val` (correctly rounded) and the self-host path used the
rational scaler, so **the bootstrap and the self-hosted compiler disagreed about
what a float literal means**. One conversion now serves both. `make fpc-check`
passes — the FPC-built compiler produces a byte-identical `pascal26` — which is
the strongest available confirmation that the two paths agree.

### Verified

- the 490-value sweep that found the bug: **byte-identical to CPython**, 0
  mismatches (was 23).
- `float("<text>") != <the same text as a literal>` over the same 490 values,
  inside one pxx program: **0** (was 23).
- `test/lex_float_literal.pas` (wired into `test-core`): every value the sweep
  caught, by name, plus the extremes, subnormals, `DBL_MAX`, the 19-digit
  `9223372036854775808.0` overflow guard, and the ordinary values that were
  already right — a correctness fix that MOVES a correct value is a regression,
  so those rows are the point of the test as much as the failures are.
- `gate.sh quick` GREEN, self-host fixedpoint byte-identical.

### For the next reader

There are now three copies of this core: `lib/rtl/sysutils.pas`,
`compiler/exdec.inc`, `compiler/builtin/pylib.pas`. Each names the others and
says CHANGE ONE, CHANGE ALL THREE, and each is pinned by a test
(`test/lib_floattostr.pas`, `test/lex_float_literal.pas`,
`test/test_nilpy_float_repr.npy`) with CPython as the oracle. The general
problem — builtin/compiler code and `lib/rtl` cannot share source — is
[[decide-builtin-and-library-code-sharing]], still open.

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
