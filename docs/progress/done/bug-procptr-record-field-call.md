# Calling a procedural-pointer record/class field (`v.Run(args)`)

- **Type:** bug (compiler / parser — call through a proc-typed field)
- **Status:** done
- **Opened:** 2026-06-21
- **Relation:** the next `examples/adventure` blocker after `feature-nested-routines`
  (done). Independent of nested routines — reproduces with no nested routine.

## Symptom

A record/class field of a procedural type cannot be *called* through field
access. Reading/assigning the field is fine; invoking it is not.

```pascal
type
  TCmd  = procedure(x: Integer);
  TVerb = record Word: AnsiString; Run: TCmd; end;
var v: TVerb;
begin
  v.Run := @Hello;     { OK — assign }
  v.Run(99);           { FAIL — call through the field }
end;
```

```text
Expected: :=, but got:  (Kind: 74, Line: ...)
pascal26: error: unexpected token ()
```

The parser, after `v.Run`, expects an assignment (`:=`) rather than accepting a
call argument list `(...)`. So a proc-typed field in an l-value/member position
is only handled as an assignment target, not as an indirect-call target.

## Repro (no classes-as-units needed beyond builtinheap)

`/tmp/nest8.pas` in the nested-routines session reproduces; minimal:

```pascal
program p;
type TCmd = procedure(x: Integer);
     TVerb = record Word: AnsiString; Run: TCmd; end;
procedure Hello(x: Integer); begin writeln(x); end;
var verbs: array of TVerb; v: TVerb;
begin
  SetLength(verbs, 1);
  verbs[0].Run := @Hello;
  for v in verbs do v.Run(99);   { error here }
end.
```

Confirmed pre-existing on the pinned stable compiler (`stable_linux_amd64/default/pinned`).

## Where to look

- The member-access parse path (`x.field`) that decides between assignment and
  call. Top-level proc *vars* already do indirect calls (`SymProcSig` /
  procedural-type marshalling — see `project_procedural_types_arc`); the gap is
  reaching that indirect-call lowering from a **field** selector rather than a
  simple variable. The field already carries proc-sig info on assignment
  (`verbs[0].Run := @Hello` works), so the call site just needs to route a
  proc-typed field load into the existing indirect-call emit.

## Acceptance

- `v.Run(99)` and `verbs[i].Run(args)` call the stored procedure (value- and
  for-in-bound records), output-equal on all targets.
- `examples/adventure` advances past `engine.pas:933` (`v.Run(Self, rest)` in
  `TGame.Run`).

## Log

- 2026-06-21 - DONE (069eed5). `AddUField` records the field call signature
  (`UFldProcSig` from `LastTypeProcSig`); `ParseLValueAST` builds `AN_CALL_IND`
  with the field node as callee on `rec.field(`; statement parser accepts
  `AN_CALL_IND`. Records live in UClass space so `FindUField` covers them.
  Verified output-equal x86-64/i386/aarch64/arm32; self-host byte-identical.
  - SIDE FIX (same commit): the forward-decl path now persists
    `ProcParamDynDepth`/`ProcParamRecId`/`ProcParamIsConst`, not just
    `Params[].IsRef/IsArray`. A lifted nested routine's definition is deferred to
    top level, so its calls are ALWAYS lowered against the forward decl; without
    `ProcParamDynDepth` a captured `var dyn-array` actual passed the handle value
    instead of `&slot` → `SetLength` corrupted memory. (General forward-decl bug,
    not nested-routine-specific; surfaced by adventure's `AddVerb`.)
  - adventure now compiles AND runs end-to-end (help/look/quit, verb dispatch,
    world load via AddExit/AddVerb capture).
