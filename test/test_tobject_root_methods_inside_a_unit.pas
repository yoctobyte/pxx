program test_tobject_root_methods_inside_a_unit;
{ `o.Equals(x)` / `.GetHashCode` / `.ToString` inside a UNIT.

  The root methods' default bodies live in the `builtin` unit, pulled by a
  pre-scan for a dot-preceded Equals/GetHashCode/ToString — over the PROGRAM's
  tokens only. A unit's own tokens were never scanned, so TObject's rows were
  never minted and the call failed with `"Equals": no such member on this
  record/class`, while the identical call in a program compiled and ran.

  The program below mentions none of the three names itself: the whole point is
  that the UNIT's use is what has to pull them in. Overriding descendants are
  called through a static TObject reference, so virtual dispatch through the
  reserved root VMT slots is asserted too.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
uses rootmethunit;

var a, b, c: TNamed; o: TObject;
begin
  a := TNamed.Create; a.Tag := 7;
  b := TNamed.Create; b.Tag := 7;
  c := TNamed.Create; c.Tag := 9;

  WriteLn('eq     : ', EqRoot(a, b), ' ', EqRoot(a, c), ' ', EqRoot(nil, nil),
          ' ', EqRoot(a, nil));
  WriteLn('text   : ', TextOf(a), ' ', TextOf(c));

  o := TObject.Create;
  { a plain TObject compares by identity — the default body, not an override }
  WriteLn('root   : ', EqRoot(o, o), ' ', EqRoot(o, a));
  WriteLn('hash   : ', HashOf(o) = HashOf(o));
  o.Free;

  a.Free; b.Free; c.Free;
end.
