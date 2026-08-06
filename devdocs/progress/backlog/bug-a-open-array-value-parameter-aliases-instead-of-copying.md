---
summary: "An OPEN ARRAY value parameter (`x: array of Integer`) aliases the caller's data — the callee's `x[0] := n` is visible to the caller. FPC copies. A NAMED dynamic-array value param correctly aliases in both."
type: bug
track: A
prio: 50
---

# An open-array VALUE parameter aliases the caller's array instead of copying it

- **Type:** bug — Track A (parameter passing / open arrays).
- **Found:** 2026-08-06, closing out
  `bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing`, which listed this
  row and asked for it to be checked once the assignment direction was settled.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`, and
  unchanged by the aliasing fix.

## Repro

```pascal
program vparam;
type TIntArr = array of Integer;

procedure TakesNamed(x: TIntArr);        { named DYNAMIC ARRAY, by value }
begin x[0] := 555; end;

procedure TakesOpen(x: array of Integer); { OPEN ARRAY, by value }
begin x[0] := 666; end;

var a: TIntArr;
begin
  SetLength(a, 2); a[0] := 1; a[1] := 2;
  TakesNamed(a);  writeln('after TakesNamed(a) a[0]=', a[0]);
  a[0] := 1;
  TakesOpen(a);   writeln('after TakesOpen(a)  a[0]=', a[0]);
end.
```

| | `TakesNamed` (named dynarray) | `TakesOpen` (open array) |
| --- | --- | --- |
| **FPC** | `555` — caller sees it | `1` — **caller unaffected** |
| **pxx** | `555` — agrees | `666` — **diverges** |

## Why these two rows are NOT the same question

The original ticket noted these run "the opposite way" from assignment and said
whatever was decided should leave them consistent. Having measured both, they are
consistent already — the divergence is narrower than it looked:

- a **named dynamic-array** value parameter passes the reference, so the callee's
  write reaches the caller. That is FPC's reference semantics and the same rule as
  `b := a` aliasing, and pxx now matches on both.
- an **open array** parameter is a different construct: FPC passes `{data, high}`
  and a by-value open array gets a *copy* the callee may scribble on. Only this
  one is wrong in pxx.

So this is not "pick a direction" — the direction is FPC's and is already
decided. It is a plain missing copy on one parameter kind.

## Blast radius, and why the priority is not higher

Silent (no error, no crash — the caller's array quietly changes), which is the
expensive shape. But it only bites code that WRITES through a by-value open-array
parameter, which is unusual: the idiom is to read from an open array and take
`var`/`out` when mutation is intended. Reads are unaffected.

The fix costs a copy on every by-value open-array call, so it should be emitted
only when the callee actually writes to the parameter, or the cost lands on the
common read-only case. Whether that write-detection is worth it, versus always
copying, is the implementation call to make with a benchmark rather than by
reasoning.

## Gate
The repro above matching FPC on every target, plus a read-only open-array
parameter benchmark showing no regression from whatever copy strategy is chosen.
