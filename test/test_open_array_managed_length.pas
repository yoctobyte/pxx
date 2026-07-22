{$mode objfpc}
program test_open_array_managed_length;

{ Length/High/Low on open-array parameters with MANAGED (AnsiString) elements
  (bug-open-array-param-length-high-zero). Three defects conspired:
    - the var-path static->open copy-in excluded tyAnsiString elements, so the
      callee got a raw headerless address (Length = 0, High = -1);
    - the x86-64 tkLength codegen routed an IR_LEA of an ARRAY sym whose
      TypeKind is tyAnsiString (the ELEMENT type) to the managed-string branch,
      reading Length(a[0]) instead of the element count;
    - the by-ref arg marshalling passed &handle instead of the handle for a
      DYNAMIC array of AnsiString (same TypeKind-is-element-type blindspot).
  Covers var/const/by-value x fixed/dynamic x scalar/managed, plus write-back
  through the var param. FPC oracle output below. }

procedure VarStr(var a: array of AnsiString);
var i: Integer;
begin
  writeln('varstr ', Length(a), ' ', High(a), ' ', Low(a));
  for i := 0 to High(a) do a[i] := 'w' + Chr(Ord('0') + i);
end;

procedure ConstStr(const a: array of AnsiString);
begin
  writeln('conststr ', Length(a), ' ', High(a));
end;

procedure ValStr(a: array of AnsiString);
begin
  writeln('valstr ', Length(a), ' ', High(a));
end;

procedure VarInt(var a: array of Int64);
begin
  writeln('varint ', Length(a), ' ', High(a));
  if Length(a) > 0 then a[0] := 42;
end;

var
  fs: array[0..3] of AnsiString;
  fi: array[0..4] of Int64;
  ds: array of AnsiString;
  di: array of Int64;
  i: Integer;
begin
  fs[0] := 'orig0'; fs[1] := 'orig1'; fs[2] := 'orig2'; fs[3] := 'orig3';
  VarStr(fs);
  for i := 0 to 3 do write(fs[i], ' ');
  writeln;
  ConstStr(fs);
  ValStr(fs);
  VarInt(fi);
  writeln(fi[0]);
  SetLength(ds, 2); ds[0] := 'a'; ds[1] := 'b';
  VarStr(ds);
  writeln(ds[0], ' ', ds[1]);
  ConstStr(ds);
  SetLength(di, 3);
  VarInt(di);
  writeln(di[0]);
end.
