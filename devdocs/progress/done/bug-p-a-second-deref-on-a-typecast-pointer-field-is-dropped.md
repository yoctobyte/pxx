---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`PRec(raw)^.n^` — deref an INLINE typecast, take a pointer-to-string field, deref again — yields the raw heap pointer instead of the string. The deref happens; the POINTEE TYPE is lost, so the result comes back integer-ish (a `^Int64` field through the same cast is correct, which is what proves it). Parking the cast in a variable first is correct, so two spellings of one expression disagree. Wrong value, no diagnostic, no crash."
status: done
owner: claude-acp
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


---

## Fixed — 2026-08-20

### Measured root cause (the AST, not a theory)

`PXXDBG=a.ast` on the two spellings, side by side. Working (`p^.n^`):

```
#8197 kind=36 tk=23   <- DEREF, tk = tyAnsiString   CORRECT
  #8196 kind=11 tk=17 <- FIELD .n, tk = tyPointer
    #8195 kind=36 tk=5 ival=21   <- DEREF, carries the pointee rec id
      #8194 kind=3  tk=17        <- IDENT p
```

Broken (`PRec(raw)^.n^`):

```
#8198 kind=36 tk=5    <- DEREF, tk = tyRecord       WRONG
  #8197 kind=11 tk=17 <- FIELD .n, tk = tyPointer   (correct!)
    #8196 kind=36 tk=5 ival=0
      #8195 kind=39 tk=17 ival=13  <- PTR_CAST, alias row 13
        #8194 kind=3 tk=17         <- IDENT raw
```

The field resolves correctly in both. Only the OUTER deref differs, and it came
back `tyRecord` — the type `PRec` points at — which is exactly what the
alias-cast postfix loop in `pasparser_expr.inc` (~5223) assigns:

```pascal
{ After ^, type becomes the pointee }
tk      := IntToTypeKind(AliasElemTk[aliasIdx]);
recName := AliasElemRec[aliasIdx];
```

`aliasIdx` is the alias of the cast that OPENED the chain and never changes, so
every `^` in the chain is answered from it. By the second `^` the node is the
field, not the cast. All three things that hid it follow from that: the variable
spelling goes through a different loop, the `^Int64` field "works" because the
wrong tag happens to match, and one level is always fine because at one level
the node IS the cast.

### The fix — the shared predicate, not the call site

`NodePtrElem` (`compiler/pasparser_lval.inc`) already exists as "the pointee of
a pointer-valued expression", knowing AN_IDENT / AN_INDEX / AN_BINOP. It was
missing the two spellings this chain uses, so it got them — a pointer FIELD
(`UFldPtrElem*` via `ResolveNodeRec`) and an inline `AN_PTR_CAST` (the alias
row, guarding the NEGATIVE adapter markers, which are not alias rows). The
caret arm now asks the predicate about the CURRENT node and falls back to
`aliasIdx` only when it has no answer — which is exactly what the `-1`/`-2`
adapter casts need, so their behaviour is unchanged.

Same shape as `NodeMetaclassCi`, whose own header says it: one predicate that
knows every spelling beats a per-site copy that knows one, because the copy is
what goes stale.

### Siblings checked BEFORE closing

`test/test_cast_deref_chain_siblings.pas` — a doubly-nested `^.^.^`, a deref of
an ELEMENT of a pointer-array field (INDEX arm into the new FIELD arm), plus
`Length()` and a concatenation, which put the derefed value in contexts
`Writeln` does not. All five match FPC 3.2.2.

### Filed, not fixed here

- [[bug-n-inline-cast-deref-loses-a-pointer-fields-pointee]] —
  `compiler/pyparser.inc:44098` holds a BYTE-IDENTICAL copy of the broken caret
  arm. Track N's file, N deferred, so handed off. It shares `NodePtrElem`, so
  only the caret arm needs changing there.
- [[refactor-p-three-hand-rolled-postfix-loops]] — the overhaul this exposed
  and deliberately did not attempt. There are THREE hand-rolled copies of the
  `^ / .field / [i]` loop in Pascal (plus N's), and they have produced four
  separate silent wrong-value bugs, each fixed in one copy. Banked with the
  evidence rather than microfixed away.

### Tests

`test/test_cast_deref_pointer_field.pas` (the seven-row table above) and
`test/test_cast_deref_chain_siblings.pas`. The pinned binary prints the heap
address for rows 3 and 7, so both bite.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
