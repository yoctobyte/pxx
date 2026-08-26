---
summary: "Char/string-literal -> PChar conversion is decided in three places (argument passing, parameter defaults, expression result type) and each gets a different answer; two of the three segfault"
type: bug
track: P
prio: 60
status: done
---

# Three mechanisms decide what becomes a `PChar`, and they disagree

**Umbrella, opened 2026-08-26.** Three tickets, all filed 2026-08-25/26 while
varying shapes around `bug-single-char-literal-as-pchar-argument-segfaults`.
They are separate code paths — which is exactly the finding, and the reason to
hold them together rather than fix them one at a time.

## The concept, and the three places that answer it

*"When does a character-ish thing become a `PChar`, and what type does a
PChar-valued expression have?"* pxx answers that question in three unrelated
places:

| # | mechanism | shape | fpc 3.2.2 | pxx |
| --- | --- | --- | --- | --- |
| 1 | argument conversion | `Show(c)`, `c: Char` var | *rejects*: incompatible type | compiles, **SEGFAULTS** |
| 1 | argument conversion | `Show(Chr(45))` | prints `-` | compiles, **SEGFAULTS** |
| 2 | parameter-default machinery | `procedure D(p: PChar = '-')` | prints `-` | `error: a string literal cannot be the default for a non-string parameter` |
| 2 | parameter-default machinery | `procedure D(p: PChar = '--')` | prints `--` | same error |
| 3 | expression result type | `Writeln('diff=', b - a)`, both PChar | prints `diff=2` | prints `diff=` then **SEGFAULTS** |

Three is the number `devdocs/dev/root-cause-over-microfix.md` calls a design
flaw rather than a smell: *"count how many mechanisms serve the one concept —
two is a smell, three is a design flaw."*

## What each one actually gets wrong

1. **Argument conversion.** The earlier fix retagged one-character *constants*
   as the one-character string they also are. A `Char` **variable** and
   `Chr(n)` are not constants, so nothing retags them and the ordinal is passed
   where the pointer is expected. FPC's rule, measured rather than recalled: a
   character CONSTANT converts to a pointer to a NUL-terminated one-character
   string; a character VARIABLE does not convert at all and is a compile error.
   We do neither — we pass the ordinal and let it be dereferenced.
2. **Parameter defaults.** `ProcParamDefaultIsStr` + a char-pool span records a
   string default, and the refusal at `compiler/pasparser_decl.inc:1762` fires
   for any non-string parameter. **Both lengths are refused**, which is what
   separates this from the one-char family: nothing here depends on the literal
   being one character.
3. **Expression result type.** The arithmetic is right — `d := b - a` with
   `d: Integer` prints 2. What is wrong is the static type of the *un-assigned*
   result: it stays PChar, so `Writeln` picks its NUL-terminated-string overload
   and walks a pointer that is really the integer 2.

## Why one ticket

Fixing any one of these leaves the other two, and a reader of any one of them
cannot see that the rule they are implementing is already implemented
differently twice. The valuable outcome is one place that decides
char-or-literal-to-PChar and one place that types pointer arithmetic — which is
`devdocs/dev/normalise-dont-special-case.md` applied to a concept that currently
has three implementations and three different bugs.

Row 3 is arguably Track A (the type of a pointer-difference expression is not
Pascal-specific); it is held here because the concept is shared and splitting it
back out is cheap once someone is in the code.

## Gate

`make compiler/pascal26` + each row above diffed against fpc 3.2.2 +
`tools/gate.sh quick`. Two of the five rows segfault today, so a repro that
merely *compiles* is not evidence.

---

## RESOLVED 2026-08-26

| # | shape | fpc 3.2.2 | pxx now |
| --- | --- | --- | --- |
| 1 | `Show(c)`, `c: Char` var | *rejects* | **rejects**, by name |
| 1 | `Show(Chr(i))`, `i: Integer` var | *rejects* | **rejects**, by name |
| 1 | `Show(Chr(45))`, `Show(Chr(K))` | `-` | `-` |
| 2 | `procedure D(p: PChar = '-')`, `D;` | `-` | `-` |
| 2 | …the same, called `D()` | `-` | `-` |
| 2 | `procedure E(n: Integer; p: PChar = '--')`, `E(1)` | `1 --` | `1 --` |
| 2 | `procedure D(p: PChar = '--')` | `--` | `--` |
| 3 | `Writeln('diff=', b - a)`, both PChar | `diff=2` | `diff=2` |

`test/test_char_to_pchar_conversion.pas` (test-core, `test_ctp26`) pins every
converting row byte-identically against fpc; the two refusals have their own
files and are asserted as "does not compile".

### The rule, which is FPC's and was measured rather than recalled

> A character CONSTANT converts to a pointer to a NUL-terminated one-character
> string. A character VARIABLE does not convert at all.

That single sentence is what all three mechanisms disagreed about.

### 1. Argument conversion — the shape was unrecognised, not the context broken

`Show('-')`, `Show(#45)` and `Show(Dash)` were already right;
`Show(Chr(45))` passed the ORDINAL and segfaulted. The conversion keys on
`IsCharLitNode`, i.e. on the argument being a literal NODE, and `Chr(45)` was an
un-folded `AN_CALL`. So the fix is not in the conversion at all: `Chr` of a
constant now folds to the character constant it is (and `Ord` of one folds in
the same breath — they are one arm, and leaving half of it emitting a call
teaches the next reader the wrong rule).

Folding made the *other* half mandatory rather than optional: with the constant
case converting, the NON-constant case had to be refused explicitly or it would
have kept compiling and dereferencing address 45. `CoerceCharLitArg` now says so
for a `Char` value bound to a pointer parameter, in Pascal only — C's
`f((char)x)` to a `char*` is the caller's business.

### 2. Parameter defaults — and there are TWO mechanisms that fill one

The declaration-time refusal covered every non-string parameter; a char pointer
now passes the same `InitValDestTakesStrLit` test a typed-const slot does, so
the two constructs cannot drift apart.

Allowing the declaration was half the work, and the half that would have shipped
alone: **two** unrelated mechanisms fill an omitted argument. The parser fills
`D;` (`FillDefaultArgs` / `DefaultArgValueNode`, which builds the AN_STR_LIT and
gets the ordinary +8 marshalling for free); the IR loop in `ir.inc` fills `D()`
and the tail of `E(1)`, and it emitted the frozen string HANDLE, so the callee
read the length prefix and printed nothing. `D` printed `-` and `D()` printed
nothing — from one declaration, three lines apart. The test exercises both
spellings deliberately.

That split is itself worth a look one day: it is the same "count the
mechanisms" observation this umbrella was opened on, one level down. Not filed
— filing it would be the fourth ticket about the same sentence — but named here
so the next reader of `DefaultArgValueNode` knows there is a sibling.

### 3. Already fixed

The `PChar - PChar` result type was correct by the time this umbrella was taken;
the ticket was filed 2026-08-25 and something else settled it since. Verified
against its own repro, then kept as a regression row, because nothing else
pinned it.

### Not done, and deliberately

The +8 length-prefix skip is written inline at fifteen sites in `ir.inc`,
including the one added here. Unifying them is
[[refactor-centralize-managed-string-pchar-conversion]]'s job. What this ticket
owed was that the default and the written argument agree, and they do.

---

# The folded tickets, verbatim

Each section below is a ticket that was filed separately and is now
part of this one. Nothing is summarised away: the repro tables, the
measured oracle output and the located source lines are the reason
these are worth keeping, and they are reproduced unchanged.

## 1. `Show(c)` / `Show(Chr(45))` with a `PChar` parameter passes the ordinal

*(was `bug-p-a-char-value-is-accepted-where-a-pchar-is-wanted-and-segfaults`, prio 60)*

# `Show(c)` / `Show(Chr(45))` with a `PChar` parameter passes the ordinal

Found 2026-08-26 by Track P alongside
`bug-single-char-literal-as-pchar-argument-segfaults`, which fixed every
CONSTANT shape (`'-'`, `#45`, a named `const Dash = '-'`) by retagging the
literal as the one-character string it also is. These two shapes are not
constants as far as pxx is concerned, so nothing retags them and the ordinal
still goes where the pointer goes.

## Repro

```pascal
program d;
procedure Show(p: PChar);
begin Writeln(p[0]); end;
var c: Char;
begin
  c := '-';
  Show(c);        { pxx: SEGFAULT.  fpc: compile error }
  Show(Chr(45));  { pxx: SEGFAULT.  fpc: prints `-`    }
end.
```

| shape | FPC 3.2.2 | pxx (HEAD, 2026-08-26) |
| --- | --- | --- |
| `Show(c)`, `c: Char` variable | `Error: Incompatible type for arg no. 1: got "Char" expected "PChar"` | compiles, **segfaults** |
| `Show(Chr(45))` | prints `-` | compiles, **segfaults** |

FPC's rule, measured rather than recalled: a character **constant** converts to
a pointer to a NUL-terminated one-character string; a character **variable**
does not convert at all. `Chr(45)` is a constant expression there, so it is on
the converting side of that line — the boundary is CONSTNESS, not literalness.

## Two forks, and they want different answers

* **`Chr(45)`** — pxx does not constant-fold `Chr` of a literal, so the node is
  a runtime `AN_UNOP` tagged `tyChar` rather than the `AN_INT_LIT` the shared
  resolver (`IsCharLitNode`, `compiler/pasparser_name.inc`) recognises. Folding
  it would put it on the already-correct path with no new rule at all, and
  would fix the constant-expression family generally (`Chr(x)` where x is a
  const, `Succ('a')`, …). That looks like the right fix.
* **`c: Char` variable** — there is no constant to materialise, so the only
  correct answers are "refuse" (FPC's) or "keep segfaulting". Refusing is a
  strictness change: pxx's overload matching accepts `tyChar` → `tyPointer`
  today, and that same laxity is what lets `Show('-')` match the PChar overload
  at all before the retag runs. So tightening it needs the match to distinguish
  a char CONSTANT from a char VALUE, not just to drop the conversion.

Because the second half is a dialect-strictness call rather than a
mechanical fix, whoever takes this should settle it first — possibly as a
Track U `decide-*` — rather than guessing.

## Why prio 60

A wild-pointer dereference, which the owner's rule ranks high; but unlike the
literal case, both spellings are *unusual* code (passing a bare Char where the
signature says PChar), and neither is the invisible shape-dependence that made
`StrCat(buf, '-')` worth 80.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the two rows above
matching FPC. Add them to `test/test_char_literal_to_pchar_param.pas`, whose
header already notes that a char VARIABLE is deliberately absent pending this
ticket.

## 2. `p: PChar = '-'` is refused as a parameter default

*(was `bug-p-a-string-literal-is-refused-as-a-pchar-parameter-default`, prio 55)*

# `p: PChar = '-'` is refused as a parameter default

Found 2026-08-26 by Track P while fixing
`bug-single-char-literal-as-pchar-argument-segfaults` — varying the shape
across the whole "one-char literal in a PChar context" family turned up three
neighbours that are *length-independent*, i.e. genuinely different defects that
the one-char bug was merely standing next to. This is one of them.

## Repro

```pascal
program d;
procedure Deflt(p: PChar = '-');
begin Writeln(p); end;
begin Deflt; end.
```

| compiler | `= '-'` | `= '--'` |
| --- | --- | --- |
| `fpc -O- -Mobjfpc -Sh` | prints `-` | prints `--` |
| pxx (HEAD, 2026-08-26) | `error: a string literal cannot be the default for a non-string parameter` | same error |

**Both lengths are refused**, which is what separates this from the one-char
bug: nothing here depends on the literal being one character.

## Mechanism (unverified — the diagnostic's site is known, the fix is not)

The refusal is `compiler/pasparser_decl.inc:1762`. The default-value machinery
records a string default as `ProcParamDefaultIsStr` + a char-pool span
(`ProcParamDefaultSOff`/`SLen`), and `DefaultArgValueNode`
(`compiler/pasparser_call.inc`) rebuilds it as an `AN_STR_LIT` tagged with the
parameter's own string kind. A POINTER parameter has no string kind to tag it
with, so the arm was never written and the declaration is refused instead.

Likely shape of the fix: let a pointer-typed parameter take the string default,
rebuild it as an `AN_STR_LIT` tagged `tyString`, and let the existing
"auto const char* marshalling" in `IRLowerCallArg` apply the +8 length-prefix
skip — the same route a *written* `Deflt('-')` argument now takes since
`bug-single-char-literal-as-pchar-argument-segfaults`.

## Why it matters

A defaulted `PChar` parameter is ordinary C-binding shape (`nil`, `''`, a
separator). The failure is at least LOUD — a compile error, not a wrong value —
which is why this is prio 55 rather than 80.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + a repro whose output
matches FPC at both literal lengths. Add the rows to
`test/test_char_literal_to_pchar_param.pas`, which already asserts the rest of
the family.

## 3. PChar - PChar segfaults when passed straight to Writeln

*(was `bug-pchar-difference-in-writeln-arg-segfaults`, prio 55)*

# PChar - PChar segfaults when passed straight to Writeln

Found 2026-08-25 by Track B while writing the FPC-differential test for the
`strings` PChar family (`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`).
`StrECopy` returns a cursor into the destination buffer, and the natural way to
check it is `Writeln(StrECopy(d, s) - d)` — which is how this was hit.

## Repro (pdiff2.pas)

```pascal
program pdiff2;
var
  buf: array[0..15] of Char;
  a, b: PChar;
begin
  a := @buf[0];
  b := @buf[2];
  Writeln('diff=', b - a);
end.
```

| compiler | result |
| --- | --- |
| `fpc -O- -Mobjfpc` | prints `diff=2` |
| pxx (pinned stable, this checkout) | prints `diff=` then **segfaults** (exit 139) |

## The tell — the arithmetic is right, the TYPE is wrong

The identical expression assigned to an Integer first is correct:

```pascal
  d := b - a;          { d: Integer }
  Writeln('diff=', d); { prints 2 — correct on pxx }
```

So the subtraction computes 2. What goes wrong is the static type of the
un-assigned result: it stays PChar (or pointer), Writeln picks its
NUL-terminated-string overload, and dereferences address `2`. The assignment
case works only because the assignment's target type forces the conversion.

FPC/Delphi: `PChar - PChar` is a *ptrdiff*, an integer type, in every position —
not only when assigned.

## Why it matters beyond the print

The wrong inferred type is the bug; the crash is just the loudest symptom of
it. Any context that picks an overload from the expression's type — a `Writeln`,
an overloaded call, a `var` parameter — gets the pointer overload for a value
that is an integer. A crash is the cheap case; picking a different numeric
overload would be a silent wrong answer.

## Track B workaround in place

`test/lib_strings_pchar.pas` prints
`Integer(PtrUInt(p) - PtrUInt(@buf[0]))` instead. That is a TEST-side cast, not a
library reshape — no `lib/rtl` code was bent around this. Revert the cast to the
plain `p - @buf[0]` when this is fixed.

## Gate

Track A: `make compiler/pascal26` (self-host fixedpoint) + the repro above
printing `diff=2` and exiting 0.

## Log
- 2026-08-26 — resolved, commit 48efb280b.
