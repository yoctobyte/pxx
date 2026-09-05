program test_method_untyped_param_self_shift;
{$mode objfpc}
{ The implicit Self injected at parameter slot 0 shifts every per-param array
  with it. `puntyped` was the last one that did not, so a METHOD's untyped
  parameter flag sat one slot to the LEFT of its parameter: the first declared
  param answered "untyped" and the real untyped one answered "typed".

  ASSERTED AS A RELATION -- the method must behave like the byte-identical FREE
  routine -- so this test carries no per-target constant and no expected width,
  and reads the same on every backend.

  The cast-as-lvalue arm is the observable: it is legal on an untyped parameter
  precisely because such a parameter has no declared width to disagree with,
  and a size error on any typed one. Before the fix, on pin fe1e9c37d322:
    FreeUntyped  accepted        MethUntyped  REFUSED  (fail-closed)
    FreeTyped    refused         MethTyped    ACCEPTED (an 8-byte store into
                                              a 4-byte slot -- silent, no
                                              diagnostic, the dangerous half)
  The MethTyped half cannot be asserted from inside a running program, so it
  lives in the ticket with its measured output; this file pins the half that a
  program can observe, in both spellings.
  bug-p-the-self-shift-forgets-puntyped-so-a-method-param-is-mislabelled }

type
  TBox = class
    constructor Make;
    { two params, so the off-by-one has somewhere to land }
    procedure W(a: Integer; out b);
    procedure W3(a: Integer; c: Integer; out b);
  end;

constructor TBox.Make; begin end;
procedure TBox.W(a: Integer; out b); begin Integer(b) := 40 + a; end;
procedure TBox.W3(a: Integer; c: Integer; out b); begin Integer(b) := a + c; end;

procedure FreeW(a: Integer; out b); begin Integer(b) := 40 + a; end;
procedure FreeW3(a: Integer; c: Integer; out b); begin Integer(b) := a + c; end;

var
  box: TBox;
  mv, fv, mv3, fv3: Integer;
  bad: Integer;
begin
  bad := 0;
  box := TBox.Make;

  mv := 0; fv := 0;
  box.W(2, mv);
  FreeW(2, fv);
  if mv <> fv then begin writeln('MISMATCH W: method ', mv, ' free ', fv); bad := bad + 1; end;

  { three params: the flag has two slots to be wrong by }
  mv3 := 0; fv3 := 0;
  box.W3(5, 7, mv3);
  FreeW3(5, 7, fv3);
  if mv3 <> fv3 then begin writeln('MISMATCH W3: method ', mv3, ' free ', fv3); bad := bad + 1; end;

  { and the values themselves, so a pair that is equal because BOTH are wrong
    still fails -- an equality-only check would pass on two identical zeros }
  if mv <> 42 then begin writeln('W wrong value ', mv); bad := bad + 1; end;
  if mv3 <> 12 then begin writeln('W3 wrong value ', mv3); bad := bad + 1; end;

  if bad = 0 then writeln('METHUNTYPED OK')
  else writeln('METHUNTYPED FAILED ', bad);
end.
