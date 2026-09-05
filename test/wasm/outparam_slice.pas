program outparam_slice;
{ A managed `out` parameter's entry clear is emitted as its OWN CompileAST
  call, before the declared body — so every routine here builds its wasm
  function in at least two chunks, and two out params build it in three.

  Every routine reports what it saw ON ENTRY. That is the whole point: the
  dropped chunk was the clear, so the caller's stale value surviving into the
  callee is the observable, and printing it is a direct witness rather than an
  inference from the result. }

type
  TIntArr = array of Integer;

procedure OutStr(out s: AnsiString);
begin
  writeln('  OutStr entry=[', s, ']');
  s := s + 'X';
  s := s + 'Y';
end;

function OutStrF(out s: AnsiString): Integer;
begin
  writeln('  OutStrF entry=[', s, ']');
  s := s + 'X';
  OutStrF := 42;
end;

{ THREE chunks: two clears and the body. A resume that only ever fired once
  would pass every assertion above this one. }
procedure TwoOut(out a: AnsiString; out b: AnsiString);
begin
  writeln('  TwoOut entry=[', a, '][', b, ']');
  a := a + 'A';
  b := b + 'B';
end;

{ The other direction. `var` is NOT cleared, and a resume that fired for every
  by-reference parameter would clear it — which no assertion about `out` can
  see. }
procedure VarStr(var s: AnsiString);
begin
  writeln('  VarStr entry=[', s, ']');
  s := s + 'V';
end;

{ FPC clears only MANAGED out params: an ordinal one behaves exactly like var,
  and zeroing it here would be a divergence in the other direction. }
procedure OutOrd(out n: Integer);
begin
  writeln('  OutOrd entry=', n);
  n := n + 1;
end;

procedure OutDyn(out d: TIntArr);
begin
  writeln('  OutDyn entry-len=', Length(d));
  SetLength(d, 1);
  d[0] := 7;
end;

var
  s: AnsiString;
  n, r: Integer;
  d: TIntArr;
  a, b: AnsiString;
begin
  s := 'KEEP';  OutStr(s);           writeln('OutStr  after=[', s, ']');
  s := 'KEEP';  r := OutStrF(s);     writeln('OutStrF after=[', s, '] r=', r);
  a := 'PA'; b := 'PB'; TwoOut(a, b); writeln('TwoOut  after=[', a, '][', b, ']');
  s := 'KEEP';  VarStr(s);           writeln('VarStr  after=[', s, ']');
  n := 10;      OutOrd(n);           writeln('OutOrd  after=', n);
  SetLength(d, 3); d[0] := 1; d[1] := 2; d[2] := 3;
  OutDyn(d);                          writeln('OutDyn  after-len=', Length(d), ' [0]=', d[0]);
end.
