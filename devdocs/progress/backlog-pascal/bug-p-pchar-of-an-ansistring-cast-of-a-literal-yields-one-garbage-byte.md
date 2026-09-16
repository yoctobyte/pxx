---
slug: bug-p-pchar-of-an-ansistring-cast-of-a-literal-yields-one-garbage-byte
title: "`PChar(AnsiString('lit'))` yields one garbage byte, silently"
track: P
prio: 45
type: bug
status: open
owner: ""
found-by: franks-ee
created: 2026-09-16
tags: [typecast, strings, managed-strings, pchar, silent-wrong-value]
blocked-by: []
summary: "`PChar(AnsiString('hello'))` answers a 1-byte garbage string where fpc answers `hello`. No diagnostic. `AnsiString('hello')` re-TAGS its node tyAnsiString (23) while the value underneath is still a FROZEN literal, so the tag lies about the representation; PChar's lowering then reads that tag, takes the managed-handle route through PXXPCharOf, and hands it a pointer to a length prefix. Every neighbouring spelling is correct -- `PChar(lit)`, `PChar(var)`, `PChar(string(lit))`, `PChar(expr)`, `s := AnsiString(lit)`, `Length(AnsiString(lit))`, `WriteLn(AnsiString(lit))` -- so it is invisible to anything but this exact double cast. Found by writing it in a test fixture: it created a symlink whose target was one garbage byte, and the dangling link then failed four UNRELATED assertions in a way that read exactly like an RTL defect. Diagnosed to the node level, NOT fixed: the real question is where a frozen->managed coercion gets triggered, which is a representation seam affecting every cast spelling, not a PChar special case."
---

# `PChar(AnsiString('lit'))` yields one garbage byte

## Repro

```pascal
program c; var p: PChar;
begin p := PChar(AnsiString('hello')); WriteLn('[', p, ']'); end.
```

`fpc` prints `[hello]`. pxx prints `[]` (and `[<tab>]`, length 1, in the
variant that reaches a syscall). No warning, no error.

## What is correct, which is the reason nobody has hit it

Measured, all in one program: `PChar('hello')`, `PChar(s)`, `PChar(s + 'x')`,
`PChar(Copy(...))`, `PChar(string('hello'))`, `PChar(AnsiString(s))` — every
one correct. `s := AnsiString('hello')`, `Length(AnsiString('hello'))` and
`WriteLn(AnsiString('hello'))` are correct too. **Only `PChar` applied to an
`AnsiString` cast OF A LITERAL is wrong.**

## Mechanism, from the AST rather than from reading

`PXXDBG=a.ast` on the two spellings, same program:

```
BAD   PChar(AnsiString('hello'))     GOOD  PChar(string('hello'))
  AN_PTR_CAST ival=-2  (PChar)         AN_PTR_CAST ival=-2  (PChar)
    AN_PTR_CAST ival=-1 tk=23            AN_CALL ival=-60      <- a real conversion
      literal tk=4 (tyString)              literal tk=4
```

`BuiltinScalarTypeKind('ansistring')` answers `tyAnsiString` whenever
`PXX_MANAGED_STRING` is defined, **which it is by default**. The cast door then
builds a bare `AN_PTR_CAST` (ival -1, "built-in cast") and tags it 23. Nothing
materialises the literal, so the node claims to be a managed handle over a
value that is a pointer to a frozen literal's 8-byte length prefix.

`ir.inc` then hits, in this order:

```pascal
if (ASTIVal[node] = -2) and (ASTTk[ASTLeft[node]] = Ord(tyAnsiString)) then
  { route through PXXPCharOf -- the managed-handle path }
```

before the frozen arm below it that would have added
`FrozenStrPrefixSize`. `PXXPCharOf` is given a frozen pointer and reads it as a
handle. `string(...)` escapes because it is a KEYWORD on a different path that
emits an actual conversion node.

The comment already sitting beside that code says the three `-1` spellings
"are only told apart by the cast's own tk" — this is that fragility firing.

## Two candidate sites, and why the narrow one is probably wrong

1. **At the PChar lowering** — look through an ival -1 cast to the operand's
   real representation, as `IRStrTkOf` already does for WIDTH. Three lines,
   verifiable today. It is a second path guarding against a lying tag, and
   `normalise-dont-special-case.md` says the second path is the one that stays
   broken.
2. **At the cast door** — `AnsiString(frozenExpr)` should MATERIALISE
   (`PXXStrFromLit` is the existing helper; codegen already knows
   `frozen -> PXXStrFromLit`) rather than re-tag. This is the root cause and it
   fixes every consumer, not just PChar — but it changes where frozen->managed
   coercion is triggered, and the spellings that work today (`s := AnsiString(lit)`,
   `WriteLn(AnsiString(lit))`) all currently rely on the destination driving the
   coercion. That interaction is what needs measuring before touching it.

## Notes

- **Inert until a pin** either way: `compiler/**`.
- Prio 45 rather than higher because the spelling is rare, and rather than
  lower because it is a SILENT WRONG VALUE of the kind this repo's own guide
  calls the expensive class — it cost an hour here disguised as an RTL bug.

## Reproduced independently 2026-09-16 (frank-user), and the byte is NOT garbage — it is the LENGTH

Reproduced at HEAD `68d79522668e` against `fpc -O2 -Tlinux -Px86_64` on the same
source, with five neighbouring spellings as controls in the same program. Only the
double cast diverges; **B–F are byte-identical on both compilers**, which is what
makes this a one-cell defect rather than a PChar problem:

```
                     pxx            fpc
A PChar(AnsiString('hello'))   []             [hello]      <- the defect
B PChar('hello')               [hello]        [hello]
C PChar(v)                     [hello]        [hello]
D PChar(string('hello'))       [hello]        [hello]
E AnsiString('hello')          [hello]        [hello]
F Length(AnsiString('hello'))  5              5
```

**THE OBSERVABLE IS THE STRING'S OWN LENGTH, READ AS CHARACTERS.** Printing the raw
bytes instead of the string settles it — this is the summary's *"pointer to a
length-prefix"* made visible, and it means the value is **deterministic, not
garbage**:

```
            pxx byte[0..3]      fpc byte[0..3]
'abc'       3  0 0 0            97 98 99 0
'hello'     5  0 0 0            104 101 108 108
'hello world'  11 0 0 0         104 101 108 108
```

**This is why two seats saw two different symptoms from one defect.** `WriteLn` of a
`PChar` stops at the first NUL, so what you see is the length rendered as a
character: a control code for a short string (looks *empty* on most terminals), a
printable character for a string of length 32–126, and **genuinely empty for any
length that is a multiple of 256**. The original report said *"one garbage byte"* and
this seat first saw *"empty"*; both are the same byte. **Assert on `Ord(p[0])`, never
on the printed form.**

## AND THE DEFECT DOES NOT FIRE BELOW LENGTH 2 — THE TWO SHORTEST REDUCTIONS BOTH PASS

Measured boundary, same program, both compilers:

| literal | pxx `byte[0..2]` | fpc | verdict |
| --- | --- | --- | --- |
| `''` | `0 0 0` | `0 0 0` | **agree** |
| `'x'` | `120 0 0` | `120 0 0` | **agree** |
| `'A'` | `65 0 0` | `65 0 0` | **agree** |
| `'ab'` | **`2 0 0`** | `97 98 0` | **DIVERGE** |
| `'abc'` | **`3 0 0`** | `97 98 99 0` | **DIVERGE** |

**A fixture written with `''` or a single character certifies the bug as fixed.** Both
are the first thing a reduction reaches for, and a one-character literal is presumably
typed as `Char` rather than `AnsiString` so the cast never takes the failing door —
**mechanism not established here; the BOUNDARY is measured.** Any regression test for
this must use a literal of **length ≥ 2**, and the assertion must read bytes.

*(frank-user, toko watch 2026-09-16. Probes in scratch only; nothing added to `test/`
because the fix is parked and a test for an unfixed defect belongs with the fix.)*
