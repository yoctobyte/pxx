program test_ptr_deref_vararg;
{ bug-pointer-deref-not-accepted-as-var-arg: a pointer deref p^ (and p^.field,
  p^[i]) is a valid l-value and may bind a var/out/untyped parameter. }
type
  TA = array[0..3] of LongWord;
  TR = record b: LongWord; end;
  PR = ^TR;
  PA = ^TA;

procedure SetRec(var r: TR);
begin
  r.b := 5;
end;

procedure SetWord(var x: LongWord);
begin
  x := 7;
end;

var
  rr: TR;
  p: PR;
  a: TA;
  pa: PA;
begin
  rr.b := 0;
  p := @rr;
  SetRec(p^);          { whole-record deref as var arg }
  writeln(rr.b);

  rr.b := 0;
  SetWord(p^.b);       { p^.field as var arg }
  writeln(rr.b);

  a[2] := 0;
  pa := @a;
  SetWord(pa^[2]);     { p^[i] as var arg }
  writeln(a[2]);
end.
