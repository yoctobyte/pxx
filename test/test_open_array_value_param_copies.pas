program test_open_array_value_param_copies;
{$mode objfpc}{$H+}
{ An OPEN ARRAY value parameter gets its own COPY -- FPC's rule, and the one
  parameter kind pxx got wrong: `procedure P(x: array of Integer)` then
  `x[0] := 666` was visible to the CALLER, silently, because a dynamic-array
  argument passed its handle straight through
  (bug-a-open-array-value-parameter-aliases-instead-of-copying).

  Every line below is diffed against FPC -- the rows that already agreed are
  kept deliberately, because the fix has to leave them alone: a `var` open array
  must keep aliasing, a NAMED dynamic-array value param passes the reference in
  FPC too, a named FIXED array by value already copied, and a static-array
  argument already materialised a dyn temp on the way in. }
type TIntArr = array of Integer;
     TFixed  = array[0..2] of Integer;

type TBox = class
  procedure Meth(x: array of Integer);
end;

procedure TBox.Meth(x: array of Integer);
begin x[0] := 111; end;

procedure TakesNamed(x: TIntArr);
begin x[0] := 555; end;

procedure TakesOpen(x: array of Integer);
begin x[0] := 666; end;

procedure TakesOpenVar(var x: array of Integer);
begin x[0] := 888; end;

procedure TakesConst(const x: array of Integer);
begin writeln('const sees: ', x[0], ' len=', Length(x), ' high=', High(x)); end;

{ an EMPTY array must survive the copy — no element write, which would be out
  of bounds in both compilers }
procedure LenOnly(x: array of Integer);
begin writeln('lenonly: ', Length(x)); end;

procedure TakesFixed(x: TFixed);
begin x[0] := 777; end;

{ the copy must carry a real length header, not just the data pointer }
procedure Meas(x: array of Integer);
begin
  writeln('inside: len=', Length(x), ' high=', High(x), ' last=', x[High(x)]);
  x[0] := 42;
end;

{ forwarding an open-array PARAM onward by value: the inner write must not
  reach the outer caller either }
procedure Inner(x: array of Integer);
begin x[0] := 3030; end;
procedure Outer(x: array of Integer);
begin Inner(x); writeln('outer sees after Inner: ', x[0]); end;

var a: TIntArr; f: TFixed; e: TIntArr; one: TIntArr; b: TBox;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  TakesNamed(a);   writeln('named dyn by value : ', a[0]);
  a[0] := 1;
  TakesOpen(a);    writeln('open by value      : ', a[0]);
  TakesOpenVar(a); writeln('open by var        : ', a[0]);
  a[0] := 1;
  TakesConst(a);   writeln('after const        : ', a[0]);
  Meas(a);         writeln('after Meas         : ', a[0]);
  Outer(a);        writeln('after Outer        : ', a[0]);

  f[0] := 1; f[1] := 2; f[2] := 3;
  TakesFixed(f);   writeln('named fixed by val : ', f[0]);
  f[0] := 1;
  TakesOpen(f);    writeln('open by val, fixed : ', f[0]);

  b := TBox.Create;
  TakesOpen(a);
  b.Meth(a);       writeln('method open by val : ', a[0]);
  b.Free;

  SetLength(one, 1); one[0] := 9;
  TakesOpen(one);  writeln('single element     : ', one[0]);

  SetLength(e, 0);
  writeln('empty len=', Length(e), ' high=', High(e));
  LenOnly(e);
  writeln('empty survived');
  writeln('OPEN ARRAY VALUE PARAM OK');
end.
