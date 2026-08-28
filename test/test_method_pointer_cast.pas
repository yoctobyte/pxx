{ A cast to a METHOD-POINTER type reads a bare `obj.M` as a REFERENCE, not a call.

  Delphi lets the `@` be omitted where a method pointer is wanted, so `obj.M`
  means two different things and only the context separates them. An assignment
  whose LHS is a method-pointer variable supplied that context; a CAST whose
  target is a method-pointer TYPE did not, so `TSel(s.IPick)` was parsed as a
  zero-argument call and the returned integer was reinterpreted as a
  Code/Data pair -- which segfaulted.

  Both receiver flavours are pinned because they are one concept reached two
  ways: a VARIABLE (Self is the instance) and a CLASS NAME (Self is the
  metaclass -- the RTTI blob, whose VMT lives at +24 rather than [Self+0]).
  The class arm is the one the rtl-generics corpus reaches.

  NOTE: no `{`/`}` appears inside these comments, deliberately. An inner brace
  can end an FPC comment early -- FPC and pxx disagree about nesting -- which
  silently turns the rest of the comment into code. It cost two oracle runs
  while writing this file, and a test whose ORACLE can be disabled by a comment
  edit is worse than no test. Say Code/Data, never the braced spelling.

  Output verified against FPC 3.2.2.
  bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults }
program test_method_pointer_cast;
{$MODE DELPHI}{$H+}
type
  TSel = function(A: LongInt): LongInt of object;
  TMethodRec = record Code, Data: Pointer; end;
  TSvc = class
    function IPick(A: LongInt): LongInt;
    class function CPick(A: LongInt): LongInt;
    function VPick(A: LongInt): LongInt; virtual;
  end;
  TDer = class(TSvc)
    function VPick(A: LongInt): LongInt; override;
  end;

function TSvc.IPick(A: LongInt): LongInt; begin Result := A * 3; end;
class function TSvc.CPick(A: LongInt): LongInt; begin Result := A * 2; end;
function TSvc.VPick(A: LongInt): LongInt; begin Result := A + 1; end;
function TDer.VPick(A: LongInt): LongInt; begin Result := A + 1000; end;

var
  s: TSvc;
  d: TDer;
  m: TSel;
begin
  s := TSvc.Create;
  d := TDer.Create;

  m := TSel(s.IPick);      WriteLn('inst  ', m(5));
  m := TSel(TSvc.CPick);   WriteLn('class ', m(5));

  { the cast must not defeat virtual dispatch: through a TSvc-typed
    reference to a TDer, the override has to win }
  s := d;
  m := TSel(s.VPick);      WriteLn('virt  ', m(5));

  { and an ordinary call still means what it did. `m := @s.VPick` is NOT here
    on purpose: FPC rejects the plain address-of an INSTANCE method ("Variable
    identifier expected") while we accept it -- CLAUDE.md's "we accept a form
    FPC rejects" row, a divergence rather than a defect. It cannot be pinned in
    a test whose expectations come from the FPC oracle. }
  WriteLn('call  ', TSvc(d).IPick(4));

  { ...and the INLINE form, where the cast result is read as a value rather
    than assigned: `TMethod(TSel(obj.M)).Code`. This is the shape rtl-generics
    uses to read a comparer's code half, and it needs the 16-byte Code/Data
    pair to actually exist somewhere -- there was a VALUE arm for a method
    reference but no ADDRESS arm, so it refused to lower. }
  WriteLn('inl-i ', TMethodRec(TSel(s.IPick)).Code <> nil);
  WriteLn('inl-c ', TMethodRec(TSel(TSvc.CPick)).Code <> nil);
  WriteLn('inl-d ', TMethodRec(TSel(s.IPick)).Data <> nil);
end.
