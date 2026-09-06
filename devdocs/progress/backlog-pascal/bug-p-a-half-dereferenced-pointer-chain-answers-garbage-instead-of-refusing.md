---
slug: bug-p-a-half-dereferenced-pointer-chain-answers-garbage-instead-of-refusing
track: P
prio: 45
type: bug
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "`ppp^.a` and `PPPRec(ppp)^.a` with `ppp: ^^^TRec` COMPILE and print 4310376 / 0 where the correct value is 11 / 22 -- one dereference short, applied to the pointer VALUE. fpc 3.2.2 refuses both with `Illegal qualifier`. Accepting what FPC rejects is not a defect here; printing a plausible wrong number is. The two-caret-short spellings that DO refuse show the diagnostic already exists and is simply not reached: `pp.a` (depth 2, no caret) says `a pointer has no members` and `PPRec(pp).a` says `this value has no members`, so the gap is exactly the shapes where ONE caret was written and TWO were needed. Pre-existing: identical on pin v404 (4306248 / 0), and unchanged by the implicit-deref fix in bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref, which is why it is filed rather than folded in -- the repair is a DIAGNOSTIC, not an address computation."
---

# A half-dereferenced pointer chain answers garbage instead of refusing

## Measured 2026-09-06 against `fpc 3.2.2 -Mdelphi`, and on pin v404

```pascal
type TRec = record a, b: Integer; end;
     PRec = ^TRec; PPRec = ^PRec; PPPRec = ^PPRec;
var r: TRec; p: PRec; pp: PPRec; ppp: PPPRec;
begin
  r.a := 11; r.b := 22; p := @r; pp := @p; ppp := @pp;
  WriteLn('X ', ppp^.a,          ' ', ppp^.b);   { pxx: 4310376 0   fpc: Illegal qualifier }
  WriteLn('Y ', PPPRec(ppp)^.a,  ' ', PPPRec(ppp)^.b);
  WriteLn('Z ', ppp^^^.a,        ' ', ppp^^^.b); { pxx: 11 22       fpc: 11 22 }
end.
```

`Z` is the correct spelling and is right in both compilers. `X` and `Y` are each
**one dereference short**, and pxx applies the field offset to the pointer value:
`.a` is that value truncated to four bytes, `.b` is the four bytes past it. The
same silent-wrong-value signature as the ticket this was found beside.

## The boundary — where the refusal already works

| spelling | carets written / needed | pxx | fpc |
| --- | --- | --- | --- |
| `pp.a` | 0 / 2 | `a pointer has no members` | Illegal qualifier |
| `PPRec(pp).a` | 0 / 2 | `this value has no members` | Illegal qualifier |
| `ppp^.a` | 1 / 3 | **4310376** | Illegal qualifier |
| `PPPRec(ppp)^.a` | 1 / 3 | **4310376** | Illegal qualifier |

So the diagnostic exists, in two different wordings, and is reached only when
**no** caret was written. Write one where three are needed and it goes quiet.
The refusal in `pasparser_lval.inc` is `(tk = tyPointer) and (recName = REC_NONE)`
— after a caret, `recName` is no longer `REC_NONE`, so the guard cannot fire.

## Why this is a bug and not FPC-parity nitpicking

Per CLAUDE.md, us accepting what FPC rejects is **not** a defect, and a program
that writes one caret where it needs three has a **presumed programmer error**
in it — so FPC's answer is not a specification. But the rule for that case is
explicit: *prefer the answer that leaves the mistake visible.* A number is not
that. The claim here is only that the wrong VALUE is silent, not that the
acceptance is wrong.

## What a fix has to satisfy

1. `ppp^.a` and `PPPRec(ppp)^.a` do not print a number.
2. `ppp^^^.a`, `pp^^.a`, `pp^.a`, `p.a`, `p^.a`, `PRec(x).a`, `PPRec(pp)^.a`
   all keep working — the whole point of the existing depth gate in
   `ResolveNodeRec` is that a HALF-dereferenced chain resolves to nothing while
   a complete one resolves to the record, and every one of those is complete.
3. Whatever the refusal says, it must name the field and say how many
   dereferences the value still needs; the two existing wordings say neither.

**Do not widen `(tk = tyPointer) and (recName = REC_NONE)` by dropping the
second conjunct.** `recName` is non-`REC_NONE` for every correct chain too; that
guard passes today only because the arm above it already turned the complete
chains into records. Establish which shapes reach line 3422 with a pointer in
hand before changing what happens there.
