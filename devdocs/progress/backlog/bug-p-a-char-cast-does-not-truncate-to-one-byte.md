---
track: P
prio: 40
type: bug
blocked-by: []
status: backlog
summary: "`Ord(Char(258))` answers 258 where FPC answers 2. Byte(x) and Word(x) truncate correctly, so the machinery is there -- tyChar is explicitly excluded from the narrowing mask in ir.inc, alongside tyBoolean, and only tyBoolean has a reason to be. Silent wrong value; AnsiChar is the same arm."
---

# A `Char` cast does not truncate to one byte

Found 2026-08-24 by the built-in-type-name differential while gating
[[bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree]] — it
was the single row of twenty that still disagreed with FPC after that fix, and
it is unrelated to it (reproduces with the pinned binary).

```pascal
var x: Int64;
begin
  x := 258;
  writeln(Ord(Char(x)));      { pxx 258   fpc 2   WRONG }
  writeln(Ord(AnsiChar(x)));  { pxx 258   fpc 2   WRONG }
  writeln(Byte(x));           { pxx 2     fpc 2   ok    }
  writeln(Word(x + 65280));   { pxx 2     fpc 2   ok    }
end.
```

`Byte` and `Word` are right, so the narrowing machinery exists and works. A
`Char` cast simply opts out of it.

## Where

`compiler/ir.inc`, the ordinal rvalue-cast arm (~6925):

```pascal
if (narrowSize < 8) and (castTk <> tyBoolean) and (castTk <> tyChar) and
   (castTk <> tyPointer) and TypeIsOrdinal(castTk) then
```

The comment above it explains the mask correctly — a bare rvalue cast has no
store to piggyback on, so the full-width value passes through unmasked unless
the mask is forced. Three kinds are then excluded, and they are not alike:

- `tyPointer` — right: a pointer cast is a reinterpret, not a narrowing.
- `tyBoolean` — right: a Boolean cast is "nonzero is true", not "low bit", so
  masking to one byte would turn `Boolean(256)` into False.
- `tyChar` — **no such reason.** A Char IS a one-byte ordinal, exactly like
  Byte, which is masked one line later.

So the likely fix is deleting `and (castTk <> tyChar)`. Confirm it is that
simple before believing it: check whether anything depends on a Char cast
passing a wide value through — grep for `Char(` over `compiler/**` and
`lib/**` — and check the siblings while you are there, since one arm of a
double case is exactly the shape
`devdocs/dev/normalise-dont-special-case.md` warns about. `tyWideChar` (2
bytes) and `tyUCS4Char` (4) already agree with FPC and are NOT excluded, which
is itself evidence the exclusion is an accident rather than a decision.

## Gate

Track P's, plus the four rows above matching fpc 3.2.2 on x86-64 and one cross
target, plus self-host byte-identical — the compiler's own source casts to
Char in the lexer, so this arm is load-bearing for the fixedpoint.
