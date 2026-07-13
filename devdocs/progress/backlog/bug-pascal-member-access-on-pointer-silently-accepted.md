---
prio: 45
---

# Member access on a plain Pointer is SILENTLY ACCEPTED and yields the pointer

- **Type:** bug (diagnostics / silent wrong value)
- **Track:** A — core (member-access resolution)
- **Status:** backlog — opened 2026-07-13.
- **Found by:** the class-reference-array work for fpjson — `ClassTable[k].Tag` (a class
  method through a metaclass array element) printed the blob ADDRESS instead of erroring,
  which led to the general case below.

## Reproduction
```pascal
var p: Pointer;
begin
  p := nil;
  writeln(PtrUInt(p.NoSuchThing));   { compiles. prints the pointer. }
end.
```

No error, no warning. **Any** member name on a pointer-typed value is accepted and the
expression evaluates to the pointer itself. So a typo (`obj.Nmae`) on a pointer-typed
receiver silently becomes a no-op rather than a compile error.

## Why it matters beyond typos
It hides real missing features. `ClassTable[k].Tag` — calling a class METHOD through a
metaclass array element — is not supported (the dispatch needs a compile-time class id,
which an AN_INDEX does not carry). Instead of saying so, it silently produced the class
reference and dropped the call. That is the worst possible failure mode for a gap: it looks
like it works.

Note the class-reference OPERATIONS (`ClassName` / `ClassType` / `InheritsFrom`) DO now work
on any pointer-typed node, because they need only the blob value. It is the class-METHOD
call through such a node that is missing.

## Care needed
The C frontend may lean on lax pointer member access (C-mode struct access through
pointers). Any tightening must be gated on Pascal mode, or run the full C corpus before
landing. That is why this is filed rather than fixed inline.

## Wanted
- A plain `Pointer` (no element type) with a member access → compile error naming the member.
- A class-reference (`tyPointer` whose element is `tyClass`) with a member that is NOT a
  class-reference operation → an error saying a class method needs a typed metaclass
  (`class of T`), pointing at [[feature-pascal-typed-metaclass]].

## Gate
`make test` + self-host byte-identical + the C corpus (see the care note).

## 2026-07-13 — ATTEMPTED and REVERTED. The naive guard is wrong, and here is why.

Tried the obvious thing: at the AN_FIELD builder, reject a member when the receiver's recName is
not a record/class (Pascal mode only, to leave the C frontend alone). It correctly rejected
`p.NoSuchThing` — and it BROKE a legitimate case immediately:

```pascal
type PNode = ^TNode;  TNode = record v: Integer; next: PNode; end;
...
writeln(p^.next^.v);      { rejected by the naive guard }
```

A typed pointer's record identity is NOT carried in `recName` at that point — it lives in the
symbol's `PtrElemRec` (and, for a field, `UFldPtrElemRec`), and the deref chain resolves it
elsewhere. So "recName is REC_NONE" does not mean "this has no members"; it means "the record
id is somewhere else". Reverted; `make test` (b266) caught it in one run.

**The real fix must ask the right question.** Reject only when the receiver genuinely has no
member namespace to search — i.e. it is a pointer whose PtrElemRec is REC_NONE *and* not a
record/class — rather than keying on the one field that happens to be empty at that site. That
means threading the pointee record id to the member-access decision, which is the same
information the deref chain already uses.

Do NOT retry this by tightening the same predicate; it will keep hitting valid typed-pointer
chains. Start by finding where `p^.next^` resolves its record and use that.
