---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankZ
found-by: frankD
created: 2026-09-09
summary: "FIXED 2026-09-09. `Length(p)` over ANY PWideChar answered a wild address-shaped number (4415624) where fpc answers the unit count: the operand was never normalised, so it reached the runtime tkLength path, which reads a [data-8] header off a pointer that has none. Fixed with `PXXWideFromPWChar` in builtinwide (scan for a zero UTF-16 UNIT, alloc, copy) plus a second arm at the Length operand dispatch — NOT by adding tyWideChar to IsNodePChar, which routes a wide pointer into a NARROW strlen and answers 1 for 'abcd': a plausible number replacing an obvious one. The fix CREATED and then closed a regression the ticket did not name: `^WideChar` and `PWideChar` are one type in two spellings and only the alias pulled the UTF-16 runtime, so the caret spelling stopped COMPILING — legal code refused on a spelling, and it would have shipped because the repro uses the alias. needsWide now triggers on `widechar` after a caret, measured to leave a plain WideChar VALUE pulling nothing (159512B either way). Fixture test_pwidechar_len26, six rows, byte-identical to fpc 3.2.2, every number chosen so a narrow strlen cannot produce it."
---

# The repro — and it carries the control that removes the literal

```pascal
program w;
{$mode delphi}{$H+}
var buf: array[0..4] of WideChar; p: PWideChar; i: LongInt;
begin
  buf[0] := 'a'; buf[1] := 'b'; buf[2] := 'c'; buf[3] := 'd'; buf[4] := #0;
  p := @buf[0];
  Write('index :'); for i := 0 to 4 do Write(' ', Ord(p[i])); WriteLn;
  WriteLn('Length: ', Length(p));
end.
```

```
fpc 3.2.2:  index : 97 98 99 100 0     Length: 4
pxx:        index : 97 98 99 100 0     Length: 4415624
```

**Indexing is perfect and Length is not**, on the same pointer in the same
statement pair. So the pointer is right, the payload is right, and only the
Length lowering is wrong — which is what makes this independent of the literal
binding it was filed with (`bug-p-a-string-literal-bound-to-a-pwidechar-is-emitted-narrow`,
fixed 2026-09-09; that fix does not move this row, measured).

## Where

`pasparser_expr.inc`, the Length builtin's operand dispatch:

```pascal
if (not CProgramMode) and IsNodePChar(valNode) then
  valNode := WrapPCharToString(valNode);
```

`IsNodePChar` is False for a `PWideChar`, deliberately and correctly — every one
of its callers acts on the answer by reaching for a NARROW helper. So the operand
is not wrapped and falls through to the runtime `tkLength` path, whose own
comment records that it reads a `[data-8]` header off the value: the same path
that answered 1 for an Integer.

`IsNodePWideChar` (ir.inc) now exists and answers this question for the
identifier arm; it was added by the literal-binding fix and has no Length caller
yet.

## The trap, stated because it is one character of diff away

Adding `tyWideChar` to `IsNodePChar` compiles, looks like the obvious fix, and
routes a wide pointer into `PCharToString` — a narrow `strlen`. UTF-16 `'abcd'`
is `61 00 62 00 …`, so it stops at the first zero BYTE and `Length` answers **1**.
An obviously-wrong 4415624 becomes a plausible 1: a microfix that makes the
defect invisible is strictly worse than the defect.

## The real fix

A `PWideCharToWideStr` in `builtinwide.pas` — scan for a zero UTF-16 unit,
allocate, copy — wrapped at the Length site the way `WrapPCharToString` is. The
managed wide string's Length is its unit count, so the existing runtime path then
needs to know nothing about pointers, which is the same normalisation the narrow
side already made (`refactor-centralize-managed-string-pchar-conversion`).

Note that `builtinwide` is pulled only when the program names `widestring`,
`unicodestring`, `pwidechar` or one of the four PXX transcoders
(`pasparser_prog.inc`); `pwidechar` was added there on 2026-09-09 for exactly
this reason and already covers this ticket's population.

## 2026-09-09 — FIXED. One helper, one wrap, and a THIRD thing the ticket did not name

`Length(p)` over a raw PWideChar answers the UTF-16 unit count, byte-identical
to fpc 3.2.2 on every row of `test_pwidechar_len26`.

**The runtime.** `PXXWideFromPWChar(p): Pointer` in `builtinwide.pas` — scan for
a zero UTF-16 UNIT, `PXXWideAlloc(n)`, copy. It calls `PXXWideAlloc` rather than
building a block so it cannot disagree with the rest of that file about the
layout; that function already zero-fills, writes both NUL bytes, the byte length
and `PXX_KIND_WIDESTR`. nil in, nil out; an empty run is nil too, because an
empty managed string IS the nil handle there.

**The wrap.** `WrapPWideCharToWideStr` in `pasparser_lval.inc`, beside its narrow
sibling, and the Length operand dispatch is now two arms:

```pascal
if (not CProgramMode) and IsNodePChar(valNode) then
  valNode := WrapPCharToString(valNode)
else if (not CProgramMode) and IsNodePWideChar(valNode) then
  valNode := WrapPWideCharToWideStr(valNode);
```

Two lines of it are NOT a copy of the narrow one and both are recorded at the
site. `ASTTk := tyAnsiString` rather than the callee's declared `Pointer` return
— every managed-string constructor in `builtinwide` is declared `: Pointer`, and
`IRStrWidthConv` already resolves that same mismatch one door over by stamping
`PXXWideFromStr`'s result into a hidden local; this is that stamp at AST level,
because the consumer here reads the AST. And `ProcRetStrElemTk := Ord(tyWideChar)`,
which is a fact about the CALLEE, not about the call site: the block it returns
is UTF-16 whatever the declaration says. Both are required — `IRLowerAST`'s
`tkLength` arm halves only when ASTTk is `tyAnsiString` AND `ASTStrElemTkOf` is
`tyWideChar`, and for an `AN_CALL` the second reads exactly that row. Without it
the byte length arrives unhalved and `Length` answers 8 for `'abcd'`.

Declaring the builtin `: WideString` instead would let the parser fill that row
in — rejected, because it makes the unit that IMPLEMENTS UTF-16 depend on the
type it implements.

### THE THIRD THING, and it was a REGRESSION THE FIX ITSELF CREATED

`var p: ^WideChar` and `var p: PWideChar` are one type in two spellings, and the
UTF-16 runtime's token scan could only see one of them. Before this fix that
cost nothing visible — the second spelling was as wrong as the first. After it,
`^WideChar` stopped COMPILING:

```
pascal26:7: error: PWideChar->widestring conversion needs builtinwide: name
PWideChar, WideString or UnicodeString in the program so the UTF-16 runtime is pulled
```

A legal program fpc accepts, refused on a spelling, and **it would have shipped**
— the ticket's own repro uses `PWideChar`, so the fixture was green throughout.
Found by writing the negative case out and running it, not by the gate.

`needsWide` now also triggers on `widechar` **when the preceding token is a
caret**. That keeps the reason `widechar` was excluded intact rather than
overturning it: a WideChar VALUE still pulls nothing, measured — `var c: WideChar;
s := c` builds at `code=159512B`, the same as a program with no wide anything,
against `code=163608B` once builtinwide is in. The caret is the discriminator,
not the identifier.

### The fixture

`test/test_length_of_a_pwidechar_counts_utf16_units.pas` (`test_pwidechar_len26`,
Makefile), six rows, differential against fpc 3.2.2 and byte-identical.

**Every expected number is one a NARROW strlen cannot produce**, because the
one-character version of this fix — adding `tyWideChar` to `IsNodePChar` — routes
the operand into `PCharToString`:

| row | correct | what a narrow strlen answers |
| --- | --- | --- |
| `ascii` `'abcd'` | 4 | 1 |
| `high` U+0100 U+0200 U+0300 | 3 | **0** — the first BYTE of $0100 is zero |
| `astral` surrogate pair + 2 | 4 | 1 |

A row expecting 4 that a narrow read also answers 4 would certify the bug, which
is the "choose a probe whose right answer differs from the default" rule applied
to a defect whose obvious fix is the trap. `empty` and `nil` are 0 and are the
rows that would pass if the machinery did nothing — they are controls, not
claims. `caret` is the `^WideChar` spelling and exists because of the regression
above.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2049595a3.
