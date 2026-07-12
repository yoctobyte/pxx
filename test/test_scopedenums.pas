program test_scopedenums;
{ {$SCOPEDENUMS ON}: members visible only as TEnum.member; the bare name is
  free for a later unscoped enum (bug-pascal-scopedenums-ignored / tenum4). }
type
{$SCOPEDENUMS ON}
  TEnum1 = (first, second, third);
{$SCOPEDENUMS OFF}
  TEnum2 = (zero, first, second, third);
var
  e1: TEnum1;
  e2: TEnum2;
begin
  e1 := TEnum1.first;
  writeln(Ord(e1));            { 0 — TEnum1.first, not TEnum2's }
  e1 := TEnum1.third;
  writeln(Ord(e1));            { 2 }
  e2 := first;
  writeln(Ord(e2));            { 1 — bare name = the UNSCOPED enum's member }
  case e1 of
    TEnum1.third: writeln('case-ok');
  end;
end.
