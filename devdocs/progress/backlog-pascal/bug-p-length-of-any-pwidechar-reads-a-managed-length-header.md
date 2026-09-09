---
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: unassigned
found-by: frankD
created: 2026-09-09
summary: "`Length(p)` over ANY PWideChar answers a wild number (4415624, 4411480 -- it varies with the address) where fpc 3.2.2 answers the unit count. NO LITERAL IS INVOLVED: a hand-built `p := @buf[0]` over a correct `array[0..4] of WideChar` INDEXES perfectly -- 97 98 99 100 0, identical to fpc -- and Length still answers garbage. Cause: `IsNodePChar` (ir.inc) tests the pointer base against tyChar/tyUInt8/tyInt8 and never tyWideChar, so the Length site never wraps the operand and it reaches the runtime tkLength path, which reads a [data-8] length header off a pointer that has none. THAT is where every wild number in the original ticket came from, not from a NUL scan overrunning. DO NOT FIX BY ADDING tyWideChar TO IsNodePChar: that routes a wide pointer into PCharToString, a NARROW strlen, which stops at the first zero BYTE of UTF-16 'abcd' and would make Length answer 1 -- replacing an obviously-wrong number with a plausible one, which is strictly worse than the defect. There is no PWideCharToString in the tree; building one is the real fix and serves concat, compare and WriteLn through the same funnel. Split out of bug-p-a-string-literal-bound-to-a-pwidechar-is-emitted-narrow, whose literal-binding half is fixed; this half was always independent of it."
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
