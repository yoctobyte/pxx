---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`PRec(raw)^.n^` — deref an INLINE typecast, take a pointer-to-string field, deref again — yields the raw heap pointer instead of the string. The deref happens; the POINTEE TYPE is lost, so the result comes back integer-ish (a `^Int64` field through the same cast is correct, which is what proves it). Parking the cast in a variable first is correct, so two spellings of one expression disagree. Wrong value, no diagnostic, no crash."
status: urgent
owner: unassigned
---

# P an inline typecast drops a pointer field's POINTEE TYPE

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

## Corrected root cause — the deref is NOT dropped

The first reading of the table above ("the last `^` is not applied") was
**wrong**, and varying the shape is what showed it. Widened repro, same
program plus a second pointer field `m: ^Int64` and two more spellings of the
base:

| # | expression | FPC 3.2.2 | pxx (0444d2732) |
| --- | --- | --- | --- |
| 2 | `p^.n^` — cast parked in a var | `hello` | `hello` |
| 3 | `PRec(raw)^.n^` — inline cast | `hello` | `133736324661280` |
| 4 | `PRec(raw)^.m^` — inline cast, **`^Int64`** field | `99` | `99` |
| 5 | `PRec(raw)^.k` — inline cast, scalar field | `42` | `42` |
| 6 | `o.r^.n^` — pointer field of a record, no cast | `hello` | `hello` |
| 7 | `PRec(p)^.n^` — cast of an already-typed pointer | `hello` | `133736324661280` |

Row 4 is the one that kills the first theory: the `^Int64` field derefs
**correctly** through the same inline cast. So the second `^` IS applied — what
is lost is the **pointee TYPE**. The number in row 3 is the heap address a pxx
`string` variable holds (a `string` is pointer-sized, `SizeOf` = 8), i.e. the
deref produced the right 8 bytes and then `Writeln` printed them as an integer
because the expression's type came back integer-ish instead of string. Row 4
"works" only because the default happens to match what the field really is.

Row 7 narrows it further: it is not about casting from untyped `Pointer` —
casting an already-correctly-typed `PRec` to `PRec` breaks it too. **The inline
typecast itself is what drops the field's pointer-element type**, while the
same cast assigned to a variable first (row 2) keeps it.

So look for where the postfix chain records a pointer field's pointee type —
`UFldPtrElemTk` / `UFldPtrElemRec` / `UFldPtrAlias` — and find the path that
never sets it when the base expression is a typecast. Two paths serve one
concept, which is the smell `devdocs/dev/root-cause-over-microfix.md` names.

**A wrong root cause recorded in a ticket is the failure mode this repo warns
about most; this section replaces the paragraph that was here before.**

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
