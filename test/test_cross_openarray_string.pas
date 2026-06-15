program test_cross_openarray_string;

{ Regression for ARM32 self-host wall: a routine that takes a `const ... : array
  of AnsiString` open-array param and copies its elements into managed-string
  fields, mirroring RegisterProc in the compiler. The native-emitted ARM32
  compiler segfaulted in PXXStrDecRef finalizing a hidden managed-string temp in
  such a routine. }

const MAX_SLOT = 4;

var
  Names: array[0..MAX_SLOT-1] of AnsiString;
  Depth: array[0..63] of Integer;
  Count: Integer;

procedure Register(const tag: AnsiString; nParams: Integer;
  const pnames: array of AnsiString);
var i: Integer;
begin
  Names[Count] := tag;
  for i := 0 to 15 do
    Depth[Count * 4 + i] := 0;
  for i := 0 to nParams - 1 do
    Names[Count] := pnames[i];
  Count := Count + 1;
end;

var pnames: array[0..15] of AnsiString;
begin
  Count := 0;
  pnames[0] := 'alpha';  pnames[1] := 'beta';
  Register('first', 2, pnames);
  pnames[0] := 'gamma';
  Register('second', 1, pnames);
  writeln('count=', Count);
  writeln('last=', Names[Count - 1]);
end.
