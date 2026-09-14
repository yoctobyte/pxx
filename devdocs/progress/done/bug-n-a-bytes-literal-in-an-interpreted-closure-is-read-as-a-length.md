---
slug: bug-n-a-bytes-literal-in-an-interpreted-closure-is-read-as-a-length
title: a bytes literal inside an interpreted closure reached the bytes() constructor as a string and was coerced to an int
summary: >
  A lambda's body is snapshotted as tokens and run by pyeval, and in that
  snapshot a bytes LITERAL arrives as a CALL -- `b"abcd"` reaches the
  bytes()/bytearray() constructor as bytes('abcd'). The constructor had an arm
  for a bytes object and an arm for an int and none for a string, so it
  coerced the literal's own text to an integer and raised
  `TypeError: expected a number, got str` from a lambda containing nothing but
  a literal. ParsePrimary's bytes-literal arm a few hundred lines above has
  always answered `bytes(TkText[Cur])`, "chars are the byte values" -- the two
  routes disagreed. Fixed by giving the constructor the string arm so they
  agree. Fixture test_nilpy_a_bytes_literal_inside_an_interpreted_closure.
track: N
type: bug
prio: 85
owner: frank-user
status: done
---

## Minimal

    class A:
        def steps(self):
            return [lambda g, f, t, p: len(b"abcd")]
    A().steps()[0](1, 2, 3, 4)

    pxx    TypeError: expected a number, got str
    CPython 4

The same body OUTSIDE a closure is correct, because a compiled bytes literal
never goes near pyeval.

## How it presented

lekkerzeilen `app.py:1752`, `len(indices or b"")` inside
`lambda g, f, t, p: self._reserve_mesh(stage, name, layout, len(vertices),
len(indices or b""))`. The literal is EMPTY, so the message named an empty
string and read like a missing argument rather than like a literal. A probe on
`pyvar_to_int`'s refusal arm printing the offending value -- `PROBE to_int got
str: []` -- is what turned it from "somewhere in that lambda" into three lines.

## The divergence this accepts, deliberately

`bytes("abc")` without an encoding is a TypeError in CPython. It is accepted
here, because by the time the interpreter sees it the literal and the call have
already collapsed into one spelling, so refusing would refuse the literal --
and the literal is the shape real code writes. NilPy is upward compatible with
CPython by design; recorded in `nilpy-semantics-divergences.md`.

## The alternative, not taken

The other repair is upstream: keep the bytes literal as a bytes-literal TOKEN
in the closure snapshot, so it reaches ParsePrimary's existing arm and never
becomes a call. That is more faithful and it is strictly more work, and the
constructor still needs a string arm for the call spelling to mean anything.
Worth doing if the snapshot's re-render is ever revisited for another reason.

## Guard

`test_nilpy_a_bytes_literal_inside_an_interpreted_closure`. The COMPILED read
is the positive control; the empty literal is not last, because an instrument
that only saw the empty spelling would read the failure as an arity problem;
and `bytes(n)` is a row so the fix cannot swallow the int arm. Reverted, the
fixture dies at the second line with the original message.

## Log
- 2026-09-14 — resolved, commit e013fab89.
