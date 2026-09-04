{ The objfpc CONTROL for test_generic_self_other_specialization: the same three
  fields spelled with the literal `specialize` keyword. This arm has always
  worked, and that is exactly what makes it the control -- the defect was never
  a missing feature, it was the mode-Delphi surface not reaching the machinery
  this surface reaches.

  Values must equal the program's mode-Delphi arm ROW FOR ROW. FPC 3.2.2
  compiles neither arm ("Syntax error, identifier expected"); accepting what FPC
  rejects is not a defect, and the two arms agreeing with EACH OTHER is the
  claim being made here.
  bug-p-a-different-specialization-of-the-same-template-inside-its-own-body }
unit uselfspec;
{$mode objfpc}

interface

uses SysUtils;

type
  generic TBoxO<T>   = class V: T; end;
  generic TOuterO<T> = class
    V: T;
    FBox:   specialize TBoxO<ShortInt>;   { a DIFFERENT template            }
    FSelf:  specialize TOuterO<T>;        { same template, same args        }
    FOther: specialize TOuterO<ShortInt>; { same template, DIFFERENT args   }
  end;

function ObjfpcArm: AnsiString;

implementation

function ObjfpcArm: AnsiString;
var o: specialize TOuterO<LongInt>;
begin
  o := specialize TOuterO<LongInt>.Create;
  o.V := 1000000;
  o.FOther := specialize TOuterO<ShortInt>.Create;
  o.FOther.V := 7;
  o.FSelf := o;
  o.FBox := specialize TBoxO<ShortInt>.Create;
  o.FBox.V := 3;
  { SizeOf of the two V fields is the row that matters: 1 against 4 is the only
    assertion that can tell a genuine second specialization from FOther having
    been collapsed into the enclosing one. Both are wrong-if-collapsed and
    neither collides with a type default. }
  Result := IntToStr(o.V) + ' ' + IntToStr(o.FOther.V) + ' ' +
            IntToStr(o.FSelf.V) + ' ' + IntToStr(o.FBox.V) + ' ' +
            IntToStr(SizeOf(o.FOther.V)) + ' ' + IntToStr(SizeOf(o.V));
end;

end.
