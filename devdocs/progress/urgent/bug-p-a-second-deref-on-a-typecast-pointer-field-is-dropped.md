---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`PRec(raw)^.n^` — deref a typecast pointer, take a POINTER field, deref again — silently drops the last `^` and yields the raw pointer value instead of what it points at. Assigning the cast to a variable first (`p := PRec(raw); p^.n^`) is correct, so the two spellings of one expression disagree. Wrong value, no diagnostic, no crash."
status: urgent
owner: unassigned
---

# P a second `^` on a typecast pointer's pointer field is dropped

- **Track P** (the Pascal postfix/lvalue chain — `compiler/pasparser_lval.inc`).
- Found while widening `TypeInfo(T)` ([[feature-typeinfo-all-types]]); it is
  **not** a TypeInfo bug — the first repro was
  `PTypeInfo(TypeInfo(Integer))^.NamePtr^`, but it reproduces with an ordinary
  user record and no `typinfo` unit at all.
- Filed at prio 70 rather than the usual: it produces a **plausible wrong value
  with no diagnostic**, which is this repo's expensive failure mode, and it is
  reachable from ordinary C-interop-shaped Pascal.

## Repro (diffed against FPC 3.2.2)

```pascal
program cast1;
type
  PStr = ^string;
  TRec = record k: Int64; n: PStr; end;
  PRec = ^TRec;
var r: TRec; s: string; raw: Pointer; p: PRec;
begin
  s := 'hello'; r.k := 42; r.n := @s; raw := @r;
  p := PRec(raw);
  Writeln('via var:  ', p^.n^);
  Writeln('via cast: ', PRec(raw)^.n^);
  Writeln('one lvl:  ', PRec(raw)^.k);
end.
```

| line | FPC 3.2.2 | pxx (af2a96072) |
| --- | --- | --- |
| `p^.n^` (cast parked in a var) | `hello` | `hello` |
| `PRec(raw)^.n^` (cast inline) | `hello` | `123158885564448` |
| `PRec(raw)^.k` (one level, scalar field) | `42` | `42` |

So the chain is fine for one level and fine through a variable; it is the
**second `^`, on a POINTER field, after an inline typecast deref** that is
dropped. The printed number is the field's raw pointer value — the final deref
is not mis-taken, it is simply not applied.

## Why this is the double-case shape

`devdocs/dev/normalise-dont-special-case.md` names exactly this: one construct
reachable through two shapes (cast parked in a variable vs cast used inline),
where the second shape is the one that stays broken. **Do not fix the inline
case by special-casing it** — find where the postfix loop stops extending the
chain after a typecast-deref base and make both shapes take the same path.
Before closing, grep for the siblings: `PRec(raw)^.n^.field`,
`PRec(raw)^.arr[i]^`, and a method call on the derefed field.

Note `compiler/pyparser.inc` may carry its own copy of the postfix chain — check
it and **file** rather than edit if it does (Track N's file).

## Gate

`make compiler/pascal26` + the repro above + `tools/gate.sh quick`. The test
that bites is the three-row diff, not just the middle row — the point is that
the two spellings must AGREE.
