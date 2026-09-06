---
track: P
prio: 60
type: bug
status: open
blocked-by: []
owner:
summary: "`PP(Self)^.__ClassRef.Go(args);` -- a class method reached through a class-reference FIELD, in STATEMENT position -- is rejected with `statement is neither a call nor an assignment`, the marker sitting on the `(` of the argument list. A REGRESSION: pin v404 fe1e9c37d322 compiles it, HEAD does not. It is the second of two regressions in the same window blocking corpus rung 6a (generics.defaults:1865, EXTENDED_HASH_FACTORY.GetHashList); the first was bug-p-a-nested-record-field-cannot-see-a-sibling-nested-type and is fixed, which is what exposed this one. NOT bisected yet -- the window is the 63 commits in 5b5fdb0b3..de4bf2245 and the harness to do it is in the sibling ticket."
---

# A class method through a class-ref field is not accepted as a statement

## Reproducer

Needs the nested-alias fix in place to reach the wall at all; before that it
stops earlier with `unknown type`.

```pascal
program g3;
{$mode delphi}
type
  TOpts = set of (oA, oB);
  TFac = class
  public type
    TFacClass = class of TFac;
    PPVMT = ^PVMT;
    PVMT = ^TVMT;
    TVMT = record __ClassRef: TFacClass; end;
  public
    class procedure Go(AKey: Pointer; n: Integer; opts: TOpts = []); virtual; abstract;
    class procedure Int8(constref v: Shortint);
  end;

class procedure TFac.Int8(constref v: Shortint);
begin
  PPVMT(Self)^.__ClassRef.Go(@v, SizeOf(System.Shortint), []);
end;

begin
end.
```

```
pin fe1e9c37d322   compiles
HEAD               error: statement is neither a call nor an assignment
                   near: ) ^ . __ClassRef . Go >>> ( @ v
```

The `>>>` marker sits on the `(` of the argument list, so the statement parser
walked `PP(Self)^.__ClassRef.Go` and then declined to treat the following `(`
as a call.

## Where it bites

`generics.defaults.pas:1865` and the fifteen sibling lines under it, via
`{$DEFINE EXTENDED_HASH_FACTORY := PPExtendedEqualityComparerVMT(Self)^.__ClassRef}`.
This is the wall corpus rung 6a currently stops at.

## What is already ruled out

Each of these compiles at HEAD, so none of them alone is the trigger:

- a class-ref field reached through a single pointer deref and cast, called in
  statement position (`PVMT(p)^.__ClassRef.Go(7)`)
- the same through a DOUBLE pointer with an implicit inner deref
  (`PPVMT(ppv)^.__ClassRef.Go(7, [])`)
- both of the above with the types declared at unit level rather than nested

The difference in the failing case is that the types are nested in the class
and the receiver is a cast of `Self` inside a class method of that same class.
**Which of those two matters has not been separated** — do that before
bisecting, it is two probes.

## How to bisect it

The window is the 63 commits in `5b5fdb0b3` (pin v404) `..de4bf2245`. The sibling
ticket's harness builds at a sha and reports GOOD/BAD in one line, seeding from
the pin with the `touch` after the `cp` and refusing the result unless the build
says `converged after` AND the built sha differs from the seed. Six steps.

Filed rather than fixed because the sibling regression was the one blocking the
rung first, and this one wants its own boundary established before a bisect —
running one against an unseparated shape is how a window gets attributed to the
wrong commit.
