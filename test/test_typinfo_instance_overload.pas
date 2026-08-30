{ `GetPropInfo(AnObject, 'Caption')` -- the spelling every FPC consumer uses --
  bound typinfo's `PClassRTTI` arm instead of the `TObject` arm, and segfaulted.

  The narrowing in MatchParamCompatible that is supposed to stop a class argument
  binding a pointer parameter read the parameter's pointee from
  `Syms[Procs[i].Params[j].SymIdx]`. That symbol no longer exists by the time a
  caller is matched: SymRollbackTo hands a routine's symbol indices back at scope
  exit, so the slot has been reused. It did not read a stale value -- it read
  whatever the CALLER's own scope had since allocated there. Measured, with the
  `p.ptrparam` channel:

    REG   proc=GetPropInfo i=0 sym=363 elemtk=5 (tyRecord)  name=cls kind=2
    MATCH proc=GetPropInfo j=0 sym=363 ptrelem=0 (tyUnknown) name=o   kind=1

  -- `o` being this test's own variable. And because tyUnknown is the
  untyped-pointer sentinel, the guard FAILED OPEN: it permitted the class
  argument, the pointer arm stayed viable, and it was then preferred over the
  exact class match.

  Fixed by reading the durable `ProcParamPtrElemTk` column instead, which lives
  as long as the Proc. That is the fourth member of a family defs.inc already
  documents three times (ProcParamRecId, ProcParamSetEnumId, ProcParamProcSig),
  each saying a param symbol does not outlive the callee's scope.

  WHY THIS TEST USES REAL typinfo. Every synthetic two-overload repro tried --
  in a program and across a unit interface -- selects correctly even on the
  broken compiler, because their parameters' element types happen to be recorded
  in a slot nothing has reused yet. The defect needs a pointee whose symbol is
  genuinely gone, which is what a unit's interface gives. Do not "simplify" this
  test into a local overload pair; it would pass on the bug. }
program test_typinfo_instance_overload;

{$MODE OBJFPC}

uses typinfo;

type
  TThing = class(TObject)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

var
  o: TThing;
  pi: PPropInfo;
begin
  o := TThing.Create;
  o.Caption := 'hi';
  { binds the TObject arm; before the fix this bound PClassRTTI and segfaulted }
  pi := GetPropInfo(o, 'Caption');
  if pi = nil then
  begin
    writeln('typinfo-overload nil');
    Halt(1);
  end;
  { and the arm it bound must be the RIGHT one, not merely a non-crashing one:
    read the value back through the PropInfo it returned. }
  writeln('typinfo-overload ', GetStrProp(Pointer(o), pi));
end.
