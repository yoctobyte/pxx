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
