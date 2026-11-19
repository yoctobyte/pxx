{ A call0 body with managed locals and several returns calls one out-of-line
  release sweep (ProcSweepThunkAddr). When the body is emitted a second time
  (a forward branch that did not reach), the sweep's address from the first
  pass must be forgotten, or every later return calls into the middle of
  other code. feature-xtensa-codegen-density-before-register-allocation }
program bas;
type TBig = record neg: Boolean; limbs: array of Integer; end;
function Mk(n: Integer; ng: Boolean): TBig;
var r: TBig;
begin SetLength(r.limbs, n); r.neg := ng; Mk := r; end;
function F(const a, b: TBig): TBig;
var r: TBig; c: Integer;
begin
  if a.neg = b.neg then
  begin
    r := Mk(1, a.neg);
    F := r;
    Exit;
  end;
  c := Length(a.limbs) - Length(b.limbs);
  if c = 0 then
  begin
    SetLength(r.limbs, 0);
    r.neg := False;
    F := r;
    Exit;
  end;
  if c > 0 then r := Mk(3, a.neg) else r := Mk(4, b.neg);
  F := r;
end;
var x: TBig;
begin
  x := F(Mk(1, False), Mk(1, False)); writeln(Length(x.limbs), x.neg);
  x := F(Mk(1, False), Mk(1, True)); writeln(Length(x.limbs), x.neg);
  x := F(Mk(2, False), Mk(1, True)); writeln(Length(x.limbs), x.neg);
  x := F(Mk(1, False), Mk(2, True)); writeln(Length(x.limbs), x.neg);
end.
