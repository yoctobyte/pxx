program test_concat_intrinsic;

{ Concat(s1, ..., sn) — the System string-concatenation intrinsic (chained `+`),
  available with no `uses`. Covers multi-arg, single-arg, and mixed literals.
  FPC oracle: abc / x / hello world. }

var s: string;
begin
  s := Concat('a', 'b', 'c');                WriteLn(s);   { abc }
  s := Concat('x');                          WriteLn(s);   { x }
  WriteLn(Concat('hel', 'lo', ' ', 'world'));              { hello world }
end.
