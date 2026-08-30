---
title: Other frontends
order: 66
---

# Other frontends

`pxx --version` lists twelve frontends:

```
  frontends:   pascal c nilpy rust zig ada basic fortran algol erlang lolcode whitespace
```

Four of those have pages of their own — Pascal, [C](./c-frontend.md),
[Nil Python](./nil-python.md), and BASIC below. This page accounts for the rest,
because a name in that list is **not** a support claim, and the difference
between the two kinds is worth stating plainly rather than leaving a reader to
infer it from silence.

## The short version

| Frontend | What it is | Build on it? |
| --- | --- | --- |
| Pascal, C, Nil Python | Full frontends, documented, gated by their own test suites | Yes |
| **BASIC** | A real frontend with its own dialect and regression tests | Yes, within its surface |
| Rust, Zig | Experimental, deliberately parked at a proof-of-concept | No |
| Ada, Fortran, Algol, Erlang, LOLCODE, Whitespace | **Skeleton probes** — one test each | No |

## BASIC is a real frontend

Not an esoteric probe. It is a free-form BASIC dialect with line numbers,
`GOTO`/`GOSUB` including nested calls through a return stack, `IF … THEN`,
`PRINT`, and `LET`-less assignment:

```basic
10 PRINT "A"
20 GOTO 50
30 PRINT "SKIPPED"
50 I = 0
60 I = I + 1
70 IF I < 3 THEN GOTO 60
80 PRINT "looped ", I
```

It carries several regression tests rather than one skeleton, and it is one of
the frontends used to demonstrate cross-language import.

## The probes, and what they are actually for

Ada, Fortran, Algol, Erlang, LOLCODE and Whitespace are **skeleton frontends**:
a lexer and a parser for a trivial subset, lowering straight onto the *existing*
shared IR — no new IR primitives, no new backend work. Each has exactly one test,
and all six compile and run today.

**The point is not that PXX compiles Fortran.** These exist to prove the shared
AST and IR are correct, by feeding them programs shaped unlike anything the
mainline frontends produce. Column-position-sensitive lexing, implicit typing by
a variable's first letter, dynamic loose casting, a `GOTO`-first control flow —
each stresses a path Pascal, C and Nil Python never reach. "Oh, and it compiles
Fortran" is the side effect people notice; the differential test of the pipeline
is the actual deliverable. This is the same argument
[Nil Python](./nil-python.md) makes for itself, taken further: a
structurally different source language is the cheapest way to find a bug in
shared internals.

So the honest summary of a probe is: **it works, it is one test wide, and it is
not going anywhere.** None of them competes for priority against real work, and
none should be read as a promise. If you want to compile Ada, use an Ada
compiler.

## Rust and Zig

Both are real frontends under active-but-optional development, and both are
**experimental**: picked up on request or for fun, never ranked against
mainline work. Rust is deliberately parked at the state that proved the concept.
Treat them the same way as the probes for planning purposes — the difference is
ambition, not current support.

## Next

- [C Frontend](./c-frontend.md)
- [Nil Python](./nil-python.md)
- [Cross languages](./cross-languages.md)
