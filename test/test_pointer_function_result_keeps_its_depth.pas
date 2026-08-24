program test_pointer_function_result_keeps_its_depth;
{ A function RESULT of pointer type keeps the whole pointer shape -- pointee,
  depth and ultimate base -- so `GetQ^` on a `function GetQ: ^PChar` is a PChar
  and `GetQ^[i]` is a Char, exactly as they are for a variable of that type.

  Before the fix the proc table recorded the immediate pointee alone, and PChar
  and ^PChar have the SAME immediate pointee once you only look one step: every
  row here printed an address. Two readers had to learn it, not one -- the
  declaration-side metadata (ProcRetPtrDepth / ProcRetPtrBaseTk / Rec) and the
  call-result suffix walk, which is a fourth copy of the pointer walk and
  stamped none of the node tags IsNodePChar and IRPointerStride read. That
  split is why `c := GetQ^; WriteLn(c)` printed the string while
  `WriteLn(GetQ^)` printed the address.

  .expected IS fpc 3.2.2's own output on this source.
  bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape }
{$mode objfpc}
type
  PPChar = ^PChar;

  TBox = class
    F: PPChar;
    function Get: PPChar;
  end;

var
  s: PChar;
  q: PPChar;
  b: TBox;
  c: PChar;

function TBox.Get: PPChar;
begin
  Result := F;
end;

function GetQ: PPChar;
begin
  Result := q;
end;

function GetQArg(k: Integer): PPChar;
begin
  if k = 0 then Result := q else Result := nil;
end;

begin
  s := 'hello';
  q := @s;
  b := TBox.Create;
  b.F := @s;
  WriteLn('deref   : ', GetQ^);
  WriteLn('witharg : ', GetQArg(0)^);
  WriteLn('method  : ', b.Get^);
  WriteLn('index   : ', GetQ^[1], GetQ^[4]);
  WriteLn('midx    : ', b.Get^[1]);
  c := GetQ^;
  WriteLn('viavar  : ', c);
  WriteLn('concat  : ', 'x' + GetQ^);
  WriteLn('compare : ', GetQ^ = 'hello');
end.
