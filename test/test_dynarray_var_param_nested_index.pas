program test_dynarray_var_param_nested_index;
{ Indexing a by-ref (var/out) dynamic-array parameter. IR_SLOTADDR is the
  address of the LOCAL slot; for a var param that slot holds the ADDRESS of the
  caller's handle, so every nested index aimed one indirection short — at the
  parameter's own slot. `d[0] := nil` nulled the ROOT handle and
  `SetLength(d[0], 3)` RESIZED the root. SetLength on the root itself was always
  right (it comes in through IR_LEA), so the two halves of one statement
  disagreed about what `d` meant.
  bug-a-setlength-on-a-2d-dynarray-var-param-is-lost }
type
  TDA = array of Integer;
  TD2 = array of TDA;
  TD3 = array of TD2;
  TS  = array of AnsiString;
  TS2 = array of TS;

procedure Nil0(var d: TD2);   begin SetLength(d, 2); d[0] := nil; end;
procedure Plain(var d: TD2);  begin SetLength(d, 2); end;
procedure Rows(var d: TD2);
begin
  SetLength(d, 2); SetLength(d[0], 2); SetLength(d[1], 1);
  d[0][0] := 5; d[0][1] := 6; d[1][0] := 7;
end;
procedure Deep(var d: TD3);
begin
  SetLength(d, 2); SetLength(d[1], 2); SetLength(d[1][1], 2);
  d[1][1][0] := 8; d[1][1][1] := 9;
end;
procedure One(var d: TDA);    begin SetLength(d, 3); d[0] := 99; end;
procedure Strs(var d: TS2)  ;
begin
  SetLength(d, 2); SetLength(d[0], 2);
  d[0][0] := 'ab'; d[0][1] := d[0][0] + 'c';
  { overwrite a row so the old row must be released exactly once }
  d[0] := nil;
  SetLength(d[0], 1); d[0][0] := 'z';
end;

function Sum2(const d: TD2): Integer;
var i, j: Integer;
begin
  Result := 0;
  for i := 0 to High(d) do for j := 0 to High(d[i]) do Result := Result + d[i][j];
end;

var a2: TD2; a3: TD3; a1: TDA; s2: TS2; ok: Integer;
begin
  ok := 0;
  SetLength(a2, 7); Nil0(a2);  if Length(a2) = 2 then Inc(ok);
  SetLength(a2, 7); Plain(a2); if Length(a2) = 2 then Inc(ok);
  Rows(a2);
  if (Length(a2) = 2) and (a2[0][0] = 5) and (a2[0][1] = 6) and (a2[1][0] = 7) then Inc(ok);
  if Sum2(a2) = 18 then Inc(ok);                    { const param, read path }
  Deep(a3);
  if (Length(a3) = 2) and (Length(a3[1]) = 2) and
     (a3[1][1][0] = 8) and (a3[1][1][1] = 9) then Inc(ok);
  SetLength(a1, 7); One(a1);
  if (Length(a1) = 3) and (a1[0] = 99) then Inc(ok);  { depth 1 — always worked }
  Strs(s2);
  if (Length(s2) = 2) and (Length(s2[0]) = 1) and (s2[0][0] = 'z') then Inc(ok);
  WriteLn('total ok ', ok, ' / 7');
end.
