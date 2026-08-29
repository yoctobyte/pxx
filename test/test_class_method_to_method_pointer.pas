{ A CLASS method assigned to a method-pointer variable must become a method
  REFERENCE, not a call.

  m := TSvc.CPick used to parse as AN_CALL: the class method was invoked with
  the class as its hidden self and the returned Int64 stored into the 16-byte
  Code/Data target, so calling `m` jumped to that integer. It compiled clean
  and segfaulted at run time. The instance twin m := s.IPick was always
  correct -- the Delphi @-optional arm that builds AN_METHODREF opens with
  FindSym, which resolves a variable, so a class receiver fell straight through.

  The VIRTUAL rows are the ones that matter for the lowering: a class method's
  Self is the RTTI BLOB, whose VMT sits at +24, NOT an instance whose VMT is at
  [Self+0]. Dereferencing a blob as though it were an object reads its name
  pointer as a VMT -- which would give a plausible wrong code pointer rather
  than a crash, so both a base-declared and an overridden virtual are asserted
  here and must answer differently.

  bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults }
program test_class_method_to_method_pointer;
{$MODE DELPHI}{$H+}
type
  TMethodRec = record Code, Data: Pointer; end;
  TSel = function (A: LongInt): LongInt of object;

  TBase = class
    class function CPick(A: LongInt): LongInt; virtual;
  end;

  TSvc = class(TBase)
    class function CPick(A: LongInt): LongInt; override;
    class function CPlain(A: LongInt): LongInt;
    function IPick(A: LongInt): LongInt;
  end;

class function TBase.CPick(A: LongInt): LongInt; begin Result := A * 100; end;
class function TSvc.CPick(A: LongInt): LongInt;  begin Result := A * 2;   end;
class function TSvc.CPlain(A: LongInt): LongInt; begin Result := A * 7;   end;
function TSvc.IPick(A: LongInt): LongInt;        begin Result := A * 3;   end;

var
  m: TSel;
  p: Pointer;
  s: TSvc;
begin
  s := TSvc.Create;

  { instance receiver -- was always correct, kept as the control }
  m := s.IPick;      WriteLn(m(5));
  m := s.IPick;      p := TMethodRec(m).Code;  WriteLn(PtrUInt(p) <> 0);

  { class receiver, non-virtual }
  m := TSvc.CPlain;  WriteLn(m(5));
  m := TSvc.CPlain;  p := TMethodRec(m).Code;  WriteLn(PtrUInt(p) <> 0);

  { class receiver, VIRTUAL -- the two must dispatch differently }
  m := TSvc.CPick;   WriteLn(m(5));
  m := TBase.CPick;  WriteLn(m(5));

  { plain address of a class method -- was always correct }
  p := @TSvc.CPlain; WriteLn(PtrUInt(p) <> 0);
end.
