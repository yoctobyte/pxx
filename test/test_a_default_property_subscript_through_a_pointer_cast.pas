{ A DEFAULT PROPERTY SUBSCRIPTED DIRECTLY ON A POINTER-ALIAS CAST.

  `t := PTC(raw)^[3]` answered 0 with NO ACCESSOR CALLED — the hand-rolled
  cast walk built a raw AN_INDEX straight over the object — while
  `t := pc^[3]` (same subscript, plain variable) and `t := PTC(raw)^.A[3]`
  (same property, named explicitly, same cast) both answered 77 through the
  getter. fpc 3.2.2 answers 77 for all three. Silent wrong value, one spelling
  of three, pre-dating pin v403.

  The shared selector walker has always known the whole rule — getter, setter,
  the multi-index group, and the PropAccessIsWrite lookahead that chooses
  between them. The `.name` arm of this loop delegated to it; the `[` arm never
  did. Fixed by handing it the bracket rather than teaching this loop a fourth
  copy of a four-arm rule.

  THE THREE ROWS ARE THE POINT. A cast row alone cannot tell a fixed walk from
  a language that never allowed the shape; the variable row was right
  throughout, and the named-property row says the property itself was always
  reachable — so what was broken is the SPELLING, not the feature. Row 4 is the
  store face through the variable, which pins the setter half of the same
  property.

  Assignment THROUGH the cast (`PTC(raw)^[3] := v`) is still refused — a
  diagnostic, not a wrong value — and is the hand-off convention tracked in
  refactor-p-one-lvalue-path-for-statements-and-expressions. }
program test_a_default_property_subscript_through_a_pointer_cast;
type
  TC = class
    arr: array[0..3] of Integer;
    function GetA(i: Integer): Integer;
    procedure SetA(i, x: Integer);
    property A[i: Integer]: Integer read GetA write SetA; default;
  end;
  PTC = ^TC;
var o: TC; pc: PTC; raw: Pointer; t: Integer;
function TC.GetA(i: Integer): Integer; begin WriteLn('  [GetA]'); Result := arr[i]; end;
procedure TC.SetA(i, x: Integer); begin WriteLn('  [SetA]'); arr[i] := x; end;
begin
  o := TC.Create; o.arr[3] := 77; pc := @o; raw := pc;
  WriteLn('1 var  subscript'); t := pc^[3];        WriteLn('  t=', t);
  WriteLn('2 cast subscript'); t := PTC(raw)^[3];  WriteLn('  t=', t);
  WriteLn('3 cast named');     t := PTC(raw)^.A[3]; WriteLn('  t=', t);
  WriteLn('4 var  store');     pc^[3] := 23;       WriteLn('  arr3=', o.arr[3]);
end.
