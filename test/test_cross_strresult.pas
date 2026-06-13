program test_cross_strresult;

{ Cross-target string-result ABI oracle: a function whose Result is a legacy
  inline string struct (tyString) returns the struct's address. The global
  Result slot lives in BSS; the epilogue must hand back its address, not load a
  word from it. Same output on every target as on x86-64. }

function Pick(b: Boolean): string;
begin
  if b then
    Pick := 'yes'
  else
    Pick := 'no';
end;

function Tag(n: Integer): string;
begin
  Tag := 'n=';
end;

var
  s: string;
begin
  writeln(Pick(True));
  writeln(Pick(False));
  s := Pick(True);
  writeln(s);
  writeln(Tag(7));
end.
