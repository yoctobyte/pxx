---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`var R: TRec = (n: 7; ev: nil);` is refused with 'parenthesised initializer requires an array variable'. FPC accepts it — a var initialiser takes the same parenthesised record form a typed CONST does, and the const form already works here. One shape, two spellings, only one implemented."
status: done
owner: claude-A
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


## RESOLVED 2026-08-25 — and the sibling check turned it into a de-duplication

The ticket's read was right: a routing gap, not new machinery. What it did not
know is that the record-field loop had been hand-written **three** times:

1. the scalar typed-const arm in `ParseConstSection` (~110 lines),
2. the ARRAY-of-record element arm in the same routine (~85 more, subtly
   different — it handled strings explicitly instead of through
   `TryParseInitValForm`, and had no array-valued-field support),
3. …and the var arm, which is the one that did not exist at all.

Three mechanisms for one concept is the line
`devdocs/dev/root-cause-over-microfix.md` draws between a smell and a design
flaw, so the fix is an extraction rather than a fourth copy:

```pascal
procedure ParseRecordInitializerInto(symIdx, recId, elemIdx: Integer; isLocal: Boolean);
```

`elemIdx` is `PI_ELEM_NONE` for a plain record and the flat element index inside
an array — the emitter already combined `Elem` + `FOff`, so the array case was
never anything but a parameter. Four call sites now: const scalar, const
array-of-record element, var scalar, var array-of-record element.

**The sibling check the ticket demanded found a real second bug.** With the
scalar var form fixed, `var A: TArr = ((n: 1; s: 'a'), (n: 2; s: 'b'))` failed
with *"not a constant"*: the var section's initialiser loop tracks paren DEPTH
for N-D arrays, so it read the element's `(` as another dimension and then met
`n` where it wanted a value. The new arm has to be tested before the
depth-tracking one, and is.

Local `var L: TP = (x: 9; y: 8)` works through the `LocalInit*` channel, same as
a local typed const.

**Known limitation, inherited and unchanged:** a LOCAL record initialiser with a
STRING field is refused — *"record constant with string fields must be global"* —
because a local init slot has no `ValAux` and its `FLen` is already spent on the
field-name span. That is the local typed-const rule, it is loud, and lifting it
means widening the local init row rather than touching this path. The test uses
an all-ordinal record for its local row and says why.

Test: `test/test_a_record_typed_var_initialiser.pas`, wired into `test-core`,
`.expected` = fpc 3.2.2's own output. It asserts the two var forms, the two
CONST forms (the extraction rewrote the path they take, so they are as much at
risk as the rows it adds), an uninitialised record var still zeroed, the local
form, and a `written` row — writing through `R` and `A[1]` afterwards, which is
the whole difference between an initialised var and a const.

Gate: `make compiler/pascal26` converged in 1 round, `tools/gate.sh quick`
GREEN, fpc-testsuite unmoved.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
