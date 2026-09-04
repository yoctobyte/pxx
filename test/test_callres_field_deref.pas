{ A `^` after a FIELD of a call result must deref the FIELD's pointee, not the
  call's. ApplyCallResultPtrSuffix answered every `^` in its suffix loop from
  elemTk/elemRec -- the returned pointer's own pointee, captured once before the
  loop -- so the first `^` was right and every later one re-read the call's
  alias.

  Both faces, both silent-or-loud:
    GetP^.pc^        printed 90 rather than 'Z' -- a Char rendered as its
                     ordinal, because the deref took the call's element kind
    GetP^.pi^ := 9   was REFUSED, "cannot assign Integer to record", because the
                     target node was stamped with the record the call points at

  The `viavar` rows are the control that says this is about the OPENER and not
  the shape: the identical chain off a plain pointer variable was correct
  throughout, on the pinned compiler too.

  Found by the escape census in refactor-p-three-hand-rolled-postfix-loops --
  this was the one postfix loop of five reaching neither ResolveDerefShape nor
  ParseClassRecordSelectors. No bug report was involved.
  Expected output is fpc 3.2.2 -Mdelphi -O1. }
program test_callres_field_deref;
type
  PInt = ^Integer;
  PPInt = ^PInt;
  PNode = ^TNode;
  TNode = record
    pi: PInt;
    ppi: PPInt;
    pc: PChar;
    arr: array[1..5] of Integer;
  end;
var
  a: TNode;
  iv: Integer;
  pv: PInt;
  s: array[0..9] of Char;
  vp: PNode;
function GetP: PNode;
begin
  GetP := @a;
end;
begin
  iv := 42; pv := @iv;
  a.pi := @iv; a.ppi := @pv;
  s[0] := 'Z'; s[1] := #0; a.pc := @s[0];
  a.arr[1] := 11; a.arr[3] := 33;
  vp := @a;

  WriteLn('viavar=', vp^.pc^);
  WriteLn('pc=', GetP^.pc^);
  WriteLn('pi=', GetP^.pi^);
  WriteLn('ppi=', GetP^.ppi^^);
  WriteLn('arr1=', GetP^.arr[1]);
  WriteLn('arr3=', GetP^.arr[3]);

  GetP^.pi^ := 9;
  WriteLn('store=', iv);
  vp^.pi^ := 7;
  WriteLn('storevar=', iv);

  WriteLn('CALLRES FIELD DEREF OK');
end.
