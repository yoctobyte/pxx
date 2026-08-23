---
track: P
prio: 40
type: bug
blocked-by: []
status: done
summary: "`Ord(Char(258))` answers 258 where FPC answers 2. Byte(x) and Word(x) truncate correctly, so the machinery is there -- tyChar is explicitly excluded from the narrowing mask in ir.inc, alongside tyBoolean, and only tyBoolean has a reason to be. Silent wrong value; AnsiChar is the same arm."
owner: claude-A
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

## FIXED 2026-08-24 (claude-A) — two defects, and the second is the one worth keeping

The ticket's guess was right and incomplete. Deleting `and (castTk <> tyChar)`
from `ir.inc`'s narrowing mask fixed `AnsiChar(258)` and left `Char(258)`
answering 258 — the same cast, two answers, from the same compiler in the same
program.

**`Char` and `Boolean` are lexer TOKENS; `AnsiChar` is an identifier.** So the
two spellings never shared a path: the identifier casts build an `AN_PTR_CAST`
with `ASTIVal = -1` (the built-in ordinal pun) and reach the narrowing arm,
while `tkChar_T` / `tkBoolean_T` built an `AN_CALL` intrinsic with a negative
id and reached something else entirely. The keyword arm now builds the same
`AN_PTR_CAST` node, so there is one cast and one lowering. That is the fix; the
mask was only the half the ticket could see.

### The Boolean exclusion did not survive the oracle either

The mask excluded `tyBoolean` with a reason attached — *"nonzero is true, not
the low bit, so masking would turn `Boolean(256)` False"*. Measured:

| | fpc 3.2.2 | pxx before |
| --- | --- | --- |
| `Ord(Boolean(2))` | 2 | 2 |
| `Ord(Boolean(255))` | 255 | 255 |
| `Ord(Boolean(256))` | **0** | 256 → True |
| `Ord(Boolean(257))` | 1 | 257 → True |
| `Ord(Boolean(512))` | **0** | 512 → True |
| `Ord(Boolean(-1))` | 255 | -1 → True |

FPC narrows to the type's width and *then* tests the byte, so `Boolean(256)`
really is False there. The comment described a rule nobody had checked against
the compiler it claimed to be following. Removed.

**The exclusion list is now exactly `tyPointer`**, which is the only member
that ever had a reason: a pointer cast is a reinterpret, not a narrowing. The
neighbouring `tyWideChar` and `tyUCS4Char` were never excluded, which is what
made the pair read as an accident rather than a decision — and they are
unchanged (`WideChar(70000)` is 4464 before and after, matching FPC).

### Verified

`test/test_ordinal_value_cast_narrows.pas`, wired into `test-core`: 21
assertions — both spellings of the Char cast against each other, the neighbours
that were always right (Byte, Word, ShortInt, WideChar, UCS4Char) so a later
edit to the mask cannot quietly lose them, the seven Boolean rows, and an
in-range cast to prove nothing else moved. `ALL OK` under fpc 3.2.2 and under
pxx on **x86-64, i386, aarch64, arm32 and riscv32**.

The Boolean rows are asserted through `Ord`, not as Booleans: a Boolean holding
a truthy byte other than 1 compares unequal to `True` under *both* compilers
(`Boolean(2) <> True`), so a Boolean-valued assertion measures that quirk
instead of the narrowing. Found by writing the test the obvious way first and
watching FPC fail it three times.

Self-host fixedpoint converged in one round — which matters here, since the
compiler's own lexer casts to Char and the ticket flagged that arm as
load-bearing. `tools/gate.sh quick` GREEN.

## Gate

`make compiler/pascal26` converged + the 21-assertion test on five targets +
FPC + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
