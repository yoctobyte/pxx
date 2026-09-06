---
slug: bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker
track: P
prio: 50
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "`property Depth: Integer read FDepth write FDepth default 16;` sets propIsDefault -- the flag that means THE DEFAULT INDEXED PROPERTY -- because pasparser_decl.inc:5711 handles the two unrelated `default` clauses with one arm. Declared BEFORE a genuine `property Items[i]: ...; default;` it STEALS the slot: `t[2]` is refused with `default property is write-only` where fpc 3.2.2 prints 100. Reverse the declaration order and both print 100, so this is ORDER-DEPENDENT and a probe that happens to declare the indexed property first sees nothing. Separately and in the same clause, only a LITERAL is accepted: `default DefaultDepth`, `default DefaultDepth + 1` and `nodefault` are all refused outright (fpc compiles all three), which is wall 3 of corpus rung 7 -- FPC's pscanner.pp:893 uses the named-constant form. `default 16` alone runs correctly, so the literal is consumed somewhere; WHERE is not established and the stray token does not reach the class-body loop. Three defects, one arm: the two `default` concepts are conflated, the value is not a constant expression, and `nodefault` is absent."
---

# `default <value>` and `default;` are different clauses sharing one arm

```pascal
property Items[i: Integer]: Integer read GetItem; default;      { THE default indexed property }
property Depth: Integer read FDepth write FDepth default 16;    { an RTTI/streaming default VALUE }
```

Unrelated features, same keyword. `pasparser_decl.inc:5711` is:

```pascal
if CurTok.Kind = tkDefault then
begin
  propIsDefault := True;
  Next;
  Eat(tkSemicolon);
end;
```

— so the value form sets `propIsDefault` too.

## The observable, and it is order-dependent

```pascal
property Depth: Integer read FDepth write FDepth default 16;   { declared FIRST }
property Items[i: Integer]: Integer read GetItem; default;
...
WriteLn(t[2]);     fpc 3.2.2: 100     pxx: error: default property is write-only
```

Swap the two declarations and **both print 100**. So a reader who writes the
indexed property first — which is the natural way to write the example — sees
nothing wrong. Measured both orders.

The diagnostic is the tell even without an indexed property present at all: for
a class whose only `default` is a scalar value clause, `t[0]` gives
`default property is write-only` where fpc gives `No default property
available`. pxx believes a default indexed property EXISTS. Same wrong flag,
visible one step earlier.

## Wall 3 of rung 7: the value must be a constant EXPRESSION

| clause | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `default 16` | compiles (but sets the wrong flag, above) | OK |
| `default DefaultDepth` | **refused**, `expected ':' before ';'` | OK |
| `default DefaultDepth + 1` | **refused** | OK |
| `nodefault` | **refused** | OK |

FPC's `pscanner.pp:893` is
`property MaxIncludeStackDepth: integer read ... default DefaultMaxIncludeStackDepth;`
which is how this was reached.

## Not established

Where the LITERAL is consumed. After `Next` past `default`, `CurTok` is the
number and `Eat(tkSemicolon)` does not take it, yet it never reaches the
class-body loop and a following property parses fine. Find that before adding a
constant-expression parse, or the new code will fight whatever is already
swallowing it.

## Shape of the fix

Split the arm. `default` followed by `;` is the indexed marker and is the only
one that may set `propIsDefault`; `default` followed by anything else is a value
clause and wants a constant expression (`nodefault` is its third spelling).
pxx has no RTTI streaming, so the VALUE itself can be parsed and discarded —
the bug is the flag and the refusal, not the semantics of the default value.

Reached from [[feature-pascal-corpus-expansion]] rung 7. Wall 1 was
`c4036925a`; wall 2 is
[[bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap]].
