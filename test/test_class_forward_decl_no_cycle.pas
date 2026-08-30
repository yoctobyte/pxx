{ The UNDER-guard direction for test_class_circular_inheritance_fail.

  A forward class declaration resolved by a later definition is ordinary, legal
  and common, and it reaches the very same write site as the cycle does. A guard
  that refused it -- or that mistook "already declared" for "already an ancestor"
  -- would break every forward-declared hierarchy while the negative test above
  still passed, so the pair has to be run together. A whitelist fails in two
  directions and only one of them is visible from the fix. }
program test_class_forward_decl_no_cycle;
type
  TBase = class;
  TDerived = class(TBase) public function Tag: Integer; end;
  TBase = class public function Tag: Integer; end;

function TBase.Tag: Integer; begin Result := 1; end;
function TDerived.Tag: Integer; begin Result := 2; end;

var b: TBase; d: TDerived;
begin
  b := TBase.Create;
  d := TDerived.Create;
  writeln(b.Tag + d.Tag, ' ', d is TBase);
end.
