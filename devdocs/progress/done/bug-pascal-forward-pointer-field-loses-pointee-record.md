---
prio: 70
---

# `PNode = ^TNode` — the forward pointer's record FIELDS never got their pointee patched

- **Type:** bug (silent wrong value — wrong field offset)
- **Track:** A — core (symtab: alias back-patch; parser: member access)
- **Status:** done
  record — it was found while working
  [[bug-pascal-member-access-on-pointer-silently-accepted]] and is its root cause.

## The defect
The classic self-referential idiom

```pascal
type
  PNode = ^TNode;
  TNode = record v: Integer; next: PNode; end;
```

declares `PNode` before `TNode` exists. `ResolvePendingPointerAliases` already fixed that
up **for the alias**, by name, at the end of the type section — so a *variable* `p: PNode`
got a correct pointee record.

A record **field** did not. `AddUField` copies the pointee out of `LastTypePointerElemRec`
at field-declaration time, which for `next: PNode` is *before* the back-patch pass runs. So
`UFldPtrElemRec[next]` kept `REC_NONE` forever, and nothing ever revisited it.

## Why it stayed hidden for so long
Losing the record id makes every field reached through a deref of that field resolve at
**offset 0**. And the first field of the pointee IS at offset 0 — so:

```pascal
writeln(p^.next^.v);       { 42 — correct, by accident: v is at offset 0 }
writeln(p^.next^.next);    { 42 — WRONG. reads v again instead of the next pointer }
```

The idiom's most-written line is the one that works. Only a *second* field read back the
wrong slot, silently. Same shape as the rest of the OOP-corpus findings: the asymmetry is
the camouflage ([[project_oop_corpus_ladder_findings]]).

Note the non-forward form was always fine — `TB` … `PB = ^TB` … `TA = record b: PB end`
resolves `PB` at field-decl time, so it never entered the pending path. The bug needed the
forward reference, i.e. exactly the linked-list/tree case.

## Fix
Remember which alias a pointer field was declared through (`UFldPtrAlias`, set from a new
`LastTypePointerAlias` that `ParseTypeKind` fills when a pointer type resolves via a NAMED
alias) and re-read it in the same pass that patches the aliases. C struct fields carry their
pointee directly and set the marker to -1, so they are excluded.

## Two siblings fixed in the same commit
- **Implicit deref `p.v`** (FPC/Delphi: means `p^.v`) built the field access over the
  POINTER, so it read an offset into the pointer VALUE and printed garbage. Now
  auto-dereferenced when the pointee is a record that actually has the member — a metaclass
  pointee is a class, not a record, so `class of T` dispatch is untouched.
- **A plain `Pointer` accepted any member name** and evaluated to the pointer itself — that
  is the sibling ticket, and it only became fixable once the pointee record was correct.

## Tests
`test/test_forward_ptr_record_field.pas` (chain reads + writes through the forward pointer,
implicit deref) and `test/test_pointer_member_fail.pas` (negative). Both wired into
`make test`.

## Gate
`make test` green + self-host byte-identical.

## Log
- 2026-07-14 — resolved, commit d5785451.
