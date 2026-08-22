---
slug: bug-a-an-anonymous-procedural-type-is-not-accepted
track: A
prio: 40
status: done
commit: 1c7a96ff6
---

# An anonymous procedural type is not accepted anywhere

```pascal
type TR = record cb: procedure(l: LongInt); v: LongInt; end;   { record field }
var  cb: procedure(l: LongInt);                                 { variable }
```

```
pascal26:2: error: unknown type: Procedure
pascal26:2: error: expected name
```

Both are ordinary Pascal and fpc 3.2.2 compiles them. The identical shape behind
a *named* alias (`type TP = procedure(l: LongInt); var cb: TP;`) always worked.

## Cause

The procedural-type grammar — ~74 lines parsing the parameter list into a
body-less `Procs[]` signature — lived **inside `ParseTypeSection`'s named-alias
arm**, keyed on the name being declared (`tnOff`/`tnLen` are passed straight
into `RegisterProcTypeAlias`). `ParseTypeKind`, which every other type position
routes through, had no `tkProcedure`/`tkFunction` case at all. So the grammar
was reachable only from the one place that names a type.

That is the same mistake as `parser.inc`'s old name, one scale down: a rule was
written where it was first needed instead of where it belongs.

## Fix

Three pieces.

1. **Extract** the signature grammar into `ParseProcTypeSignature: Integer` in
   `pasparser_decl.inc`, returning the body-less `Procs[]` index and leaving
   `CurTok` at any `of object`. The `; cdecl` directive comes with it as
   `EatProcTypeCdecl`. Both forward-declared in `pasparser_name.inc` — they are
   mutually recursive with `ParseTypeKind`, since a parameter's type is a type.
   `ParseTypeSection`'s arm shrinks to a call plus the naming it always owned.

2. **A `tkProcedure, tkFunction` arm in `ParseTypeKind`**, modelled on the
   anonymous inline *record* arm already sitting three cases above it: parse the
   signature, mint the unnamed backing, and hand back exactly the `TTypeKind` +
   `LastType*` the named alias would have — `tyPointer` with depth 1 for a plain
   procvar, the shared method-pointer `tyRecord` (`EnsureMethodPtrRec`) for
   `of object`. Every consumer downstream — `AllocVar`, the record-field walker,
   the two call sites gating on `SymProcSig` — then cannot tell the inline form
   from the aliased one.

3. **One terminator fix in `ParseDeclTypeDesc`.** Its scalar-type loop stops at
   `tkProcedure`/`tkFunction`, which is right at a *declaration* position (a
   routine follows) and wrong immediately after a `:`, where nothing but a type
   can appear. Take the type there and skip the loop.

## The second bug this uncovered

Step 3 made `var cb: procedure(...)` work at program scope but not inside a
routine, with a different and much stranger failure: the parse ran off the end
of the program. It reproduces on the **pinned** compiler and has nothing to do
with anonymous types —

```pascal
procedure Go; type TP = procedure(l: LongInt); var cb: TP; begin WriteLn('go'); end;
```

— a routine-local *named* procedural type does it too. Filed and fixed in the
same commit as `bug-a-a-routine-local-procedural-type-eats-the-body`; see that
ticket.

## Deliberately not changed

FPC rejects an anonymous procedural type in a **parameter list**
(`procedure Apply(g: function(x: Integer): Integer)`); pxx accepts it. That is
the dialect's documented laxness, and it is not locked in by the test — the
oracle cannot express it, so that row uses a named type.

An anonymous procedural **return** type (`function Pick: function(x: Integer):
Integer`) is rejected by both, and stays rejected.

## Verification

- `test/test_anonymous_procedural_type.pas`, wired into `test-core`. Anonymous
  procvars as record fields (two in one declaration, and an `of object` one),
  globals, routine locals, array elements, a `cdecl` one, and nested inside a
  second record. `after 11` and the `sizes 48 56` row check that fields
  *following* a procvar still lay out correctly — a signature parsed into the
  wrong slot would show up there before anywhere else. Byte-identical to
  fpc 3.2.2.
- Named procedural types, method pointers, typed-const procvars and genuine
  nested routines all re-verified unchanged.
- `make compiler/pascal26` self-host fixedpoint, converged in 1 round.
- `tools/gate.sh quick` green.

## Found by

`library_candidates/fpc-testsuite/.../tprocvar1.pp`, whose conformance skip
reason named three gaps of which two were already stale. Chasing the third one
down found this. The reason line now names only this.
