---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`var R: TRec = (n: 7; ev: nil);` is refused with 'parenthesised initializer requires an array variable'. FPC accepts it — a var initialiser takes the same parenthesised record form a typed CONST does, and the const form already works here. One shape, two spellings, only one implemented."
status: backlog
---

# A record-shaped `var` initialiser is refused

```pascal
type TRec = record n: Integer; ev: TEv; end;
var R: TRec = (n: 7; ev: nil);
```

```
pascal26:6: error: parenthesised initializer requires an array variable
```

FPC 3.2.2 accepts it and initialises the fields. Found 2026-08-21 while
sweeping the sibling positions for
[[bug-a-nil-is-not-accepted-as-a-method-pointer-argument]] — and deliberately
NOT folded into that fix, because it is not about `nil` at all: the same
declaration with `(n: 7; ev: SomeMethod)` or with no reference field whatever
is refused just the same. The nil ticket only found it.

## Why this is a small job

`const R: TRec = (n: 7; ev: nil)` **already works**, including the local-const
and array-of-record forms, and lands its fields through the `PendingInit*` /
`LocalInit*` channel (`pasparser_decl.inc`, the "Record typed constant" arm).
An initialised `var` is the same parse and the same channel — FPC treats a var
initialiser as a writable typed const — so this is a routing gap, not new
machinery.

The diagnostic is the giveaway: *"requires an ARRAY variable"* says the var
path learned parenthesised initialisers for arrays only and the record arm was
never wired up beside it. That is the double case
`devdocs/dev/normalise-dont-special-case.md` describes, in its usual form —
the second path is the one that stayed broken.

**Check the siblings before closing**: a var of an ARRAY OF RECORD with a
parenthesised initialiser, and a LOCAL `var` with one.

## Gate

A test asserting field values for a record var, an array-of-record var and a
local one, each against FPC 3.2.2. Self-host byte-identical + `tools/gate.sh
quick`.
