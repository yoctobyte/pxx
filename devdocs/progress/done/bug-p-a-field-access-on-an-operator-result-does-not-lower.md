---
track: P
prio: 30
type: bug
blocked-by: []
summary: "RESOLVED 2026-09-09: `(x + y).v` answered IR_UNSUPPORTED (kind 5) while `z := x + y; z.v` was correct. IRLowerAddress's field/base walk ALREADY handled a record-returning CALL as a base -- the call's IR value is the address of its hidden aggregate-result temp -- and the parser leaves an overloaded operator as an AN_BINOP that IRLowerAST turns into exactly that call. So the arm was a missing NAME, not a missing mechanism: AN_BINOP now sits beside AN_CALL there, guarded by FindOpOverload2 so a tyRecord binop with no operator still reaches its honest refusal (its own fixture). Both of the ticket's unrun probes are answered and are now rows: a CLASS-returning operator was always fine (the result is a pointer, so records only), and `(p - q).a[0]` failed identically because an index over an operator result reaches the same walk -- one fix closed both. Byte-identical to fpc 3.2.2 on all three rows."
status: done
owner: unassigned
---

# A field access on an operator result does not lower

- **Found:** 2026-09-06 (frankS), incidentally, while adding Pascal `**`. It is
  NOT a `**` bug — the first probe used `**` and the second used `+`, and both
  fail the same way.
- **Measured** at compiler `113cec9cadf1` and on `stable_linux_amd64/default/pinned`.

```pascal
{$mode objfpc}
type TFoo = record v: LongInt; end;
operator + (a, b: TFoo) r: TFoo;
begin r.v := a.v + b.v; end;
var x, y: TFoo;
begin
  x.v := 4; y.v := 5;
  WriteLn((x + y).v);      { pxx: IR_UNSUPPORTED ... (kind 5);  fpc: 9 }
end.
```

Kind 5 is `AN_BINOP` (defs.inc:501), so it is the BINOP that fails to lower,
reached through the `AN_FIELD` base rather than as a statement's value. The same
operator call is fine everywhere else — through a temporary, as a `WriteLn`
argument, compared, assigned.

## Why it is worth more than a workaround

The two spellings are the same expression and only one compiles, with no
diagnostic that says so — the message names an internal node kind. A reader hits
it, adds the temporary, and never learns there was a rule. That is the shape
this repo files rather than absorbs.

## Not established

Whether every aggregate-returning operator has it, or only records; whether
`AN_INDEX` over an operator result (`(a + b)[0]`) is the same arm. Both are one
probe each and neither was run — the finding came out of unrelated work and is
banked rather than chased.

## Resolved 2026-09-09 — the arm was a missing NAME, not a missing mechanism

`IRLowerAddress`'s field/base walk already handled a record-returning CALL used
as a field base: *"the call's IR value is the address of its hidden
aggregate-result temp (aggregates are returned by-reference), so use it
directly rather than trying to take the address of a call node."*

The parser leaves an overloaded operator as an `AN_BINOP` and only retypes it to
the operator's result type; `IRLowerAST` turns that node into `IRAppendCall`.
So it produces **the same thing the arm above is describing** — the arm simply
did not list `AN_BINOP` beside `AN_CALL`. Two spellings of one concept, one of
them handled.

Guarded by `FindOpOverload2 >= 0`, which is load-bearing: a tyRecord-tagged
`AN_BINOP` with no registered operator is the garbage-arithmetic case
`IRLowerAST` refuses by name a few thousand lines down, and it has to keep
reaching that refusal rather than being handed an address here. That is the one
way this arm could go wrong, so it has its own fixture.

### Both "not established" questions, now measured

The ticket banked two probes and ran neither. Both are one line each and both
are answered:

| question | answer |
| --- | --- |
| every aggregate-returning operator, or only records? | **records only.** A CLASS-returning operator was always fine — the result is a pointer, so nothing needs an address. |
| is `AN_INDEX` over an operator result the same arm? | **yes.** `(p - q).a[0]` failed identically; an index over an operator result reaches the same field/base walk, and one fix closed both. |

Both are rows in the fixture now, so neither can go stale as prose.

Log: fixed and closed in commit 5e5fae367.
