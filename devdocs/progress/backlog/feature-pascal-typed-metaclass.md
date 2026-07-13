---
prio: 45
---

# Typed metaclasses: `class of TFoo`, so a TClass variable can call the class's methods

- **Type:** feature
- **Track:** P — Pascal frontend
- **Status:** backlog — opened 2026-07-13.
- **Follows:** [[feature-pascal-metaclass-self]] (Self in a class method = the runtime class — landed)
- **Blocks:** [[feature-pascal-corpus-fpcunit]] if fpcunit's `TTestCaseClass` path needs it

## What works today
`Self` in a class method is the metaclass and carries the RUNTIME class, and every
route to a class method passes it (named class, through an instance, bare sibling
call). Class-reference OPERATIONS work on any class reference:

```pascal
var cr: TClass;
cr := TDerived;
writeln(cr.ClassName);              { works }
writeln(cr.InheritsFrom(TBase));    { works }
```

## What does not
Calling a class METHOD through a class-reference variable:

```pascal
var cr: TClass;
begin
  cr := TDerived;
  cr.W;      { error: member access on a bare object reference }
```

The value is right (it IS the blob pointer, and the call would pass it as Self
unchanged) — what is missing is knowing WHICH class's methods are in scope. `TClass`
is untyped: it is `class of TObject`, so only TObject's class methods should resolve
through it. FPC's answer is the TYPED metaclass:

```pascal
type
  TTestCaseClass = class of TTestCase;   { fpcunit declares exactly this }
var
  tc: TTestCaseClass;
begin
  tc := TMyTest;
  tc.Suite;        { resolves against TTestCase's class methods }
```

## Shape of the work
- `class of <ClassName>` as a type: a pointer whose PtrElemRec names the class (today
  a class reference is tyPointer / PtrElemTk=tyClass / PtrElemRec=REC_NONE — the
  REC_NONE is exactly the "untyped" part).
- Member access on a value of that type: look the method up in that class (`FindUMeth`
  on the named ci), then call it with the VALUE as Self. The call machinery already
  does the right thing — `GenMakeStaticMethodCall(mpi, selfNode)` takes any node for
  Self — so this is name resolution, not codegen.
- A constructor through a typed metaclass (`tc.Create`) is the metaclass-construct path
  that already exists (BuildMetaclassNew); wire it to the typed case.
- Assigning a class literal to a typed metaclass var should check the class descends
  from the named one.

Note the dispatch is already dynamic: because Self is a real argument, a class method
called through a metaclass variable runs with whatever class the variable holds. So
this ticket is about the FRONTEND's name resolution, not about the runtime.

## Gate
`make test` + self-host byte-identical + cross.
