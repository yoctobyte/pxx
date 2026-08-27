---
summary: "`P + '!'` where `P: shortstring` is POINTER ARITHMETIC, not concatenation — it prints an address and assigns the empty string, while the same `+` on a shortstring variable is correct"
type: bug
track: P
prio: 50
status: done
---

# A frozen-string concat operand becomes pointer arithmetic

- **Type:** bug (Pascal frontend / expression typing) — Track P
- **Opened:** 2026-08-27
- **Found by:** measured and flagged as adjacent case (1) while closing
  `bug-p-a-shortstring-function-result-prints-as-a-pointer`. Verified
  pre-existing on the pinned compiler, so it was never a regression from that
  fix — it is the same root cause reaching a second consumer.

```pascal
function P: shortstring;
begin P := 'ab'; end;
var v: shortstring; a: ansistring;
begin
  v := 'ab';
  writeln(v + '!');    { FPC ab!   pxx ab!    — the VARIABLE path was fine }
  writeln(P + '!');    { FPC ab!   pxx 4304129              }
  a := P + '!';
  writeln(a);          { FPC ab!   pxx <empty>              }
end.
```

## Root cause

The same one: `StrValTk` normalises a frozen string's *storage* kind
(`tyShortString` / `tyFixedString`) to a `tyString` **value** at every symbol
read, but a **call** node carries `Ord(Procs[pi].RetType)` — the storage kind —
verbatim at some 50 sites. So the operand reached the additive arms as
`tyShortString`, missed the concat arm (which tests `tyString` / `tyAnsiString`
/ `tyChar`) and was claimed by the **pointer-arithmetic** arm below it. No
diagnostic in either direction.

## Fix

`compiler/pasparser_expr.inc` — normalise the **operand**, immediately before
the `AN_BINOP` node is allocated, for every frozen kind that is not already
`tyString`. Excluded in C mode, where `p + 'x'` genuinely is pointer arithmetic.

This is the shape the two wraps directly above it already use, and their comment
is the argument for putting it here: *"Normalising HERE rather than adding a
third arm below is the point: every downstream arm then sees two string operands
and needs to know nothing about PChar."* Storage kind and capacity live on the
symbol, not on the value, so nothing downstream loses information.

## Outcome — FIXED, 2026-08-27

`test/test_frozen_string_concat_operand.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across nine rows: the variable path
kept as a guard, a `shortstring` result on either side of `+`, a chained
`'<' + P + '>'`, frozen + frozen (`P + S8`), frozen + variable, the assignment
form that used to produce the empty string, a **method** result, and a 200-turn
concat loop — the last because the frozen concat codegen carves its result off
the stack with no restore, so a mis-typed operand in a loop would show up as an
overflow rather than as wrong text.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7.

## Still open from the same family

Two of the three adjacent cases recorded on
`bug-p-a-shortstring-function-result-prints-as-a-pointer` remain, and both are
what `cutils.pas:1429` still needs:

- **`s[0]` is not the shortstring length byte** — `s[i]` indexes as
  `data + (i-1)`, so index 0 lands on the top byte of the 8-byte length prefix.
  Reading gives 0 where FPC gives the length; writing `#1` produced
  `$0100000000000002`. Wants index 0 to *mean the length*, which touches every
  frozen-string index site.
- **`P[1]` — indexing a frozen-string result — does not parse.**

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
