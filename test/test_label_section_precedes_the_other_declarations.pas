{ ISO Pascal orders a declaration block label, const, type, var — and pxx used
  to parse the routine-level `label` section only AFTER var/const/type/nested
  routines, so the canonical order consumed the labels and then met `var` where
  the caller wanted `begin`. Every ordering must work, at both scopes.
  bug-a-a-label-section-must-come-last-in-a-routine }
program test_label_section_precedes_the_other_declarations;

{ label first — the canonical ISO order, and the shape that failed }
function Canonical: Integer;
label done;
const Limit = 3;
type TCount = Integer;
var k: TCount;
begin
  Result := 0;
  for k := 1 to 10 do
  begin
    if k > Limit then goto done;
    Result := Result + k;
  end;
done:
end;

{ label last — the only order that used to work; must keep working }
function Trailing: Integer;
var k: Integer;
label out2;
begin
  Result := 0;
  for k := 1 to 10 do
  begin
    if k > 2 then goto out2;
    Result := Result + 100;
  end;
out2:
end;

{ label ahead of a nested routine }
function WithNested: Integer;
label skip;

  function Half(x: Integer): Integer;
  begin
    Half := x div 2;
  end;

begin
  Result := Half(10);
  if Result = 5 then goto skip;
  Result := -1;
skip:
end;

{ two labels in one section, ahead of the var block }
function TwoLabels: Integer;
label a, b;
var k: Integer;
begin
  Result := 0;
  k := 2;
  if k = 2 then goto b;
a:
  Result := Result + 1;
b:
  Result := Result + 10;
end;

begin
  WriteLn(Canonical);
  WriteLn(Trailing);
  WriteLn(WithNested);
  WriteLn(TwoLabels);
end.
