---
slug: bug-p-a-half-dereferenced-pointer-chain-answers-garbage-instead-of-refusing
track: P
prio: 45
type: bug
status: done
created: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
summary: "RESOLVED 2026-09-06, hours after filing, because the boundary table was already in hand and the repair was two lines. BOTH were needed and they are two different BUILDERS: the variable spelling `ppp^.a` reaches ParseLValueAST's field builder, the cast spelling `PPPRec(ppp)^.a` reaches the SHARED walker's -- and fixing only the first left the cast one answering 4306200 in silence. The guard that was wrong is the one whose own comment argued against it: `(tk = tyPointer) and (recName = REC_NONE)`, sitting under a note explaining that a pointer-to-record has already been auto-dereffed by then -- which is exactly why recName cannot be the test. A half-dereferenced chain arrives with the ULTIMATE base record in recName (ResolveDerefShape's true answer to a different question), so both RequireValueHasMembers and RequireRecMember pass: they ask about the RECORD, and the record is fine; what is wrong is that we are not at it yet. Now refused in both spellings with a message that says the value is still a POINTER and needs another ^. Two negative tests wired, one per builder, each asserted against fpc 3.2.2's own `Illegal qualifier` rather than assumed; the positive half is test_a_pointer_cast_dereferences_implicitly_for_a_selector, without which the pair passes just as well when the guard has been widened until nothing with a . compiles."
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

## RESOLVED 2026-09-06 — two builders, one guard, and the comment was right

Refused now in both spellings. `tools/gate.sh quick` run with the tree DIRTY:
self-host fixedpoint PASS, tier quick PASS, FPC seed canary PASS; the only RED is
the known `pinned builds live lib/rtl`, which has its own ticket and is not
dispatchable.

**The prediction written into this ticket's own `What a fix has to satisfy` was
right for once, and only because it was written as a WARNING rather than a
plan:** *"do not widen `(tk = tyPointer) and (recName = REC_NONE)` by dropping
the second conjunct ... establish which shapes reach line 3422 with a pointer in
hand."* Dropping the conjunct IS the fix — but only after the measurement showed
that every COMPLETE chain has already become a record by that line, which is the
thing the warning asked for and the thing that makes the widening safe. The same
edit made without the measurement is the wider-blast-radius shape.

**What the ticket did NOT predict, and it is half the fix:** the cast spelling
reaches a different builder in a different function, with the ultimate base
record already in hand. One guard, two sites — found by running the repro
through both spellings after the first one went green, not by reading.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
