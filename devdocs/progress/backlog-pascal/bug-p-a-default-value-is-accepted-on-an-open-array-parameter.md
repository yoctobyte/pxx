---
track: P
prio: 40
type: bug
blocked-by: []
summary: "CLOSED PENDING-COMMIT. THE 2026-09-05 EXCULPATION WAS MEASURED ON ONE OF FOUR PARAMETER PARSERS AND THE WRONG VALUE WAS STILL LIVE IN THE OTHER THREE. The refusal that landed 2026-09-01 lived in ParseSubroutine, which parses the free-routine list and a method's IMPLEMENTATION header -- so `array of string = 'x'` written in BOTH places was caught, and written in the CLASS BODY alone was not. Measured 2026-09-06: `TC.M(const a: array of string = 'x')` declared in a class body and implemented without the default compiled clean, printed High(a) = 1073741823, and segfaulted on the next call; an INTERFACE method has no implementation header at all and was never asked. So the remaining value was never diagnostic quality only. FIXED by moving the refusal into ParseParamDefaultValue -- the one function all four parsers already call -- which also puts it AHEAD of the shape checks, so `= ['x']` stops being refused as `a string parameter's default must be a string literal`, a diagnostic naming the rule it was not breaking and demanding the literal it was about to reject. The caller passes the half only it knows: ParseSubroutine's isArr is true for open / named-FIXED / named-DYNAMIC alike so it asks `isArr and (paramDynDepth <= 0)`, keeping `a: TArr = nil` legal as fpc has it; the three method parsers set their flag only on the literal `array of` spelling, so there the flag alone is the answer. Five test rows: one must-not-compile per parser, each asserting the OPEN-ARRAY reason rather than any refusal, plus a positive control across all four parsers that a named dynamic array still takes nil."
status: done
owner: ""
---

# A default value is accepted on an open-array parameter

- **Type:** bug (frontend, parameter declaration checking) — **Track P**.
- **Filed:** 2026-08-29 by the wasm32 lane, on `origin/master` at `7aba316be`.
  Target-independent; the native x86-64 build is what prints the garbage.

## Symptom

```pascal
program DefOA2;
procedure P(const a: array of string = 'x');
begin
  writeln(Length(a));
end;
begin
  P;
end.
```

```
ok: defoa2  [code=61793B  data=1976B  bss=42452B  procs=130]
435728179526
```

Compiles clean; prints a pointer read as a length. FPC rejects the declaration.

The *sensible* spelling is rejected, which is how this stayed hidden:

```pascal
procedure P(const a: array of string = ['x']);
```
```
pascal26:2: error: a string parameter's default must be a string literal
```

Note the diagnostic. It refuses the array constructor **because it wants a
string** — it has already decided this is a string parameter. The refusal is
right by accident and its stated reason is the bug, so anyone who hit it would
have written `= 'x'` to satisfy the compiler and walked straight into the
garbage above. A message that names a cause here is naming the discriminator,
not the defect.

## Root cause

`ParseArrayCtorAST` (pasparser_lval.inc:3354) documents the convention: an
open-array parameter's `TypeKind` **is the element type**, with `IsArray`
carrying the "it is an array" half. For `const a: array of string` that is
`tyAnsiString`.

The default-value check reads `TypeKind` alone, so an open-array-of-string
parameter is indistinguishable from a `string` parameter at that test, and
`ProcParamDefaultIsStr` is set on a parameter that is an array. `ir.inc`'s
default-parameter arm then materialises the frozen literal into a hidden
managed temp and passes it where the callee expects an open array's
`(data, count)` pair — hence a pointer where the length belongs.

## Fix

Test `IsArray` alongside `TypeKind` at the default-value check, and reject the
declaration outright: an open-array parameter cannot carry a default in this
dialect, so both `= 'x'` and `= ['x']` should be errors, with a message that
says *that* rather than asking for a string literal.

Deliberately NOT fixed in `ir.inc` in the same pass. Adding the `IsArray` guard
to `ir.inc`'s default-parameter arm would take the other branch and pass a raw
frozen literal to an open-array parameter — one wrong lowering traded for
another. The lowering has no correct behaviour to fall back on because the
declaration should never have been accepted; the frontend is where this ends.

## Same shape, one level up

This is the identical `TypeKind`-without-`IsArray` confusion as
`bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp` (Track
A, fixed 2026-08-29), which was six sites in `ir.inc` asking whether an
argument needs an owning managed-string temp. That one was found because
wasm32 type-checks the store and refused; this one was found while deciding
whether its default-parameter arm needed the same guard. **Worth a grep for
other readers of `Params[...].TypeKind` that never consult `IsArray`** — two
independent instances in two layers is the "three is a design flaw" counter at
two.

## Gate

Track P's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus both spellings above rejected with a message that names the real reason,
plus a `{%FAIL}` conformance case if one fits.

## Half fixed at HEAD — the wrong-value arm is gone, the wrong-REASON arm is not (frankS, 2026-09-05)

At `0bbd82cd7` (sha `7fca108e4b85`), two claims, two answers:

1. **`procedure P(const a: array of string = 'x')` no longer compiles clean.**
   It is refused, with the reasoning in the diagnostic: *"a parameter of an
   open-array or fixed-array type cannot have a default value: there is no array
   literal to write there, so the value would be a scalar whose bytes the callee
   reads as a length header."* So the misprinted length (435728179526) is
   unreachable — nothing builds to run.
2. **The array-constructor spelling still gives the wrong reason.**
   `= ['x']` is refused with `a string parameter's default must be a string
   literal` — the same wrong reason this ticket names, from the same
   `Params[i].TypeKind`-without-`IsArray` read.

So this is not a close. **Re-scope it to claim 2 and drop claim 1 from the
summary**, which is the half a reader will otherwise re-measure. Whoever takes
it: the fix is one predicate, and the wrong-value observable it used to guard is
already gone, so the remaining value is diagnostic quality only — rank
accordingly.

## Closed 2026-09-06 (frankB) — and the exculpation above was a claim about ONE PARSER

Read the 2026-09-05 section again before trusting its last line. *"The
wrong-value observable it used to guard is already gone, so the remaining value
is diagnostic quality only"* was measured with the free-routine spelling, which
is the one the 2026-09-01 guard covered. **There are four parameter parsers.**
The guard lived in `ParseSubroutine`, so it covered the free-routine list and a
method's IMPLEMENTATION header; the class-body, record-body and interface-body
parameter parsers had never been asked.

Measured 2026-09-06, at `d754eeef1`:

```pascal
type TC = class
  procedure M(const a: array of string = 'x');   { declaration only }
end;
procedure TC.M(const a: array of string);        { implementation, no default }
...
o.M;
```
```
ok: oaw.pxx
M len=1073741824 high=1073741823
N len=<segfault>
```

Compiles clean, prints a length read out of a frozen literal's prefix, and
segfaults on the next call. fpc refuses at the `=`. **Writing the default in
both places was caught and writing it in the declaration alone was not** — which
is exactly why the shape survived a fix aimed at it, and why a probe that writes
the declaration the way you would write it for a working program never reaches
the hole. An interface method is worse: it has no implementation header, so
nothing downstream ever asks.

### The fix, and why it is smaller than the ticket asked for

The ticket proposed testing `IsArray` alongside `TypeKind` at the default-value
check. That is right about the predicate and wrong about the number of places.
All four parsers already call **one** function, `ParseParamDefaultValue`, so the
refusal moved into it and out of `ParseSubroutine` — one site, four callers, one
case deleted rather than three added.

Moving it also fixed claim 2 for free, because inside that function the refusal
runs **before** the shape checks. `array of string = ['x']` had been refused as
*"a string parameter's default must be a string literal"*: an open-array
parameter records its ELEMENT kind, the stringy check saw a string parameter,
and it demanded the literal the array check was about to reject. **A refusal
that tells you to write the thing it is about to refuse is a wrong diagnostic,
not a differing one.**

`paramTakesNoDefault` is the CALLER's question and deliberately not computed
inside, because only the caller can tell an open array from a named dynamic
array. `ParseSubroutine`'s `isArr` is true for open, named-FIXED and
named-DYNAMIC alike, so it asks `isArr and (paramDynDepth <= 0)` and `a: TArr =
nil` stays legal, as fpc has it. The three method parsers set their flag only on
the literal `array of` spelling, so for them the flag alone is the answer.

### Found on the way, filed separately, NOT fixed here

Two live crashes on **interface dispatch**, both compiling clean, both correct
under fpc 3.2.2, neither involving this refusal — and the second is why this
ticket's own positive control declares an interface method but dispatches
through the class:

- [[bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults]]
- [[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]]

and one wrong refusal:

- [[bug-p-a-named-dynamic-array-default-declared-in-a-class-body-is-lost-if-the-implementation-omits-it]]

I did not establish a shared cause for any of the three and have not claimed one.
