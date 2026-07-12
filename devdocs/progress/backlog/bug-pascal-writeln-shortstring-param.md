---
prio: 40
---

# writeln of a ShortString/frozen-string PARAM prints wild memory

- **Type:** bug (codegen — frozen-string by-ref param read) — **Track A**
- **Status:** backlog — found 2026-07-12 probing Pascal Script
  ([[feature-embed-pascal-script]]).

## Symptom

```pascal
procedure Check(const S: ShortString);
begin
  writeln('got=', S, ' len=', Length(S));   { S dumps env/stack memory }
end;
var f: ShortString;
begin
  f := 'HELLO';
  Check(f);   { got=<garbage>, but len=5 and S = 'HELLO' compare TRUE }
end.
```

`Length(S)` and equality comparison read the param correctly (slot address →
length word), but the WRITELN path reads from a wrong address and dumps
process memory. Pre-existing (repros on pinned v207 and in default mode, no
--mimic-fpc needed, no managed conversion involved).

## Where hit

Pascal Script's uPSUtils lexer (`Const S: ShortString` params). Any FPC code
printing a shortstring param.

## Acceptance

writeln(S) of a tyFixedString/tyShortString param prints the value on all
paths (direct + after the managed→frozen conversion temp of 2026-07-12);
compile-run test; self-host byte-identical.
