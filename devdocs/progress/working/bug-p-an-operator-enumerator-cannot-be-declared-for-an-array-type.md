---
slug: bug-p-an-operator-enumerator-cannot-be-declared-for-an-array-type
track: P
prio: 35
type: bug
blocked-by: []
status: working
owner: frankS
created: 2026-09-08
found-by: frankS
summary: "`operator enumerator(a: TDyn): TEnum` and the same for a static `array[0..1] of Integer` are refused at the DECLARATION with `operator overloading: <T> is not a supported operand type`. fpc 3.2.2 accepts both and runs them in preference to its own built-in array iteration. The refusal is at the operator declaration, not at any for-in, so it also blocks measuring what for-in over an array WOULD do -- two of the five container families in bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin cannot be exercised in pxx at all, and any precedence rule written for them today is unexercised by construction."
---

# `operator enumerator` on an array type is refused at the declaration

Measured 2026-09-08, compiler `b2361e541c4b`, fpc 3.2.2 `-Mobjfpc`.

```pascal
type
  TDyn  = array of Integer;
  TStat = array[0..1] of Integer;
operator enumerator(a: TDyn): TEnum;  begin ... end;   { pxx: refused }
operator enumerator(a: TStat): TEnum; begin ... end;   { pxx: refused }
```

```
pascal26:15: error: operator overloading: TDyn is not a supported operand type
pascal26:18: error: operator overloading: TStat is not a supported operand type
```

fpc accepts both, and `for i in <that array>` then runs the OPERATOR rather
than the built-in element iteration — `55` and `77`, the operators' own
constants, not `5 6`.

# Why it is worth more than its volume

It is loud, so nobody gets a wrong answer from it. It ranks because of what it
does to the INSTRUMENT: `enumerator` is the one operator whose whole purpose is
to give a type an iteration meaning, and the two array families are exactly
where a container library would want one. While the declaration is refused,
`for i in <array>` can only ever take the built-in path in pxx, so the
precedence question its sibling ticket is about is not merely unanswered for
arrays — it is unaskable, and a rule written to cover all families would land
with two of them untested.

# Where

`compiler/pasparser_call.inc:573` gates which operand types an operator may be
declared for; `OPK_ENUMERATOR` is listed there beside `OPK_INC`/`OPK_DEC` as
one of the unary-ish keys. The refusal text is the general
`operator overloading: <T> is not a supported operand type`, so the array kinds
are simply absent from the accepted set rather than refused by an arm that
mentions enumerators.

Check whether the same gate refuses a `record` and a `set` operand — the set
form IS accepted today (measured, `operator enumerator(a: TSet)` compiles), so
the accepted set is not simply "scalars".
