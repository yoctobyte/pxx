---
track: B
prio: 25
type: feature
blocked-by: []
summary: "`Concat` is declared as a two-argument function, so FPC's variadic form `Concat('a','b','c')` fails to compile with `candidates: Concat(AnsiString, AnsiString)`. Loud, not silent."
status: backlog
---

# `Concat` accepts exactly two strings

- **Track B** (`lib/rtl` — unless the right answer is to make it an intrinsic,
  which would move it to Track P).
- Found 2026-08-20 by an FPC differential probe over the string RTL.

## Repro

```pascal
Writeln(Concat('a', 'b', 'c'));
```

```
pascal26: error: no matching overload
  candidates:
    Concat(AnsiString, AnsiString)
```

FPC compiles it: `Concat` there is a compiler intrinsic that folds an arbitrary
number of arguments into a chain of `+`.

## Why it is low prio

It is a compile error, so no program silently computes the wrong string, and
`a + b + c` is the form everyone actually writes. It costs a real program
nothing but a mechanical edit — which is exactly the kind of edit the
platonic-code rule says not to make, hence the ticket.

## Sketch

Either give `Concat` the same variadic treatment the other fold-style
intrinsics get in the Pascal frontend, or add the 3..8-argument overloads to
`lib/rtl` and accept that the ninth still fails. The intrinsic is the honest
fix; the overloads are the cheap one.
