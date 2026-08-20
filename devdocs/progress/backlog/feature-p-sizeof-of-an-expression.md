---
prio: 30
---

# `SizeOf` of an EXPRESSION is refused

- **Type:** feature (Pascal frontend) — tag: compat
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** backlog

## Symptom

    var b: Byte;
    writeln(SizeOf(-b));

    pxx:  error: SizeOf: expected type name
    FPC:  8

FPC's `SizeOf` accepts any expression and answers the size of its static type;
pxx accepts a type name and a variable, but not an expression built from one.

## Why it matters more than it looks

It is the natural instrument for asking "what type did the compiler infer
here", which is exactly the question
[[bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits]] turned on —
every width in that ticket's table was measured under FPC because pxx could
not be asked. `PXXDBG` covers the compiler-internals side; this is the same
question from inside a test program, where it can be an assertion.

## Note

Carried out of the parent ticket's "side finding" section, where it sat unfiled
through two sessions. Not a blocker for anything; small and self-contained.

## Gate

`SizeOf` of an expression answering FPC 3.2.2's value for each integer type and
for a float; `make compiler/pascal26`; `tools/gate.sh quick`.
