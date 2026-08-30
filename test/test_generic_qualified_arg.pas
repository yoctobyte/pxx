program test_generic_qualified_arg;
{ A QUALIFIED type name as a generic argument -- `specialize TEnum<TOuter.TPair>`.
  FPC compiles and runs this; pxx rejected it with `Expected: >, but got: .`
  because a generic argument was modelled as exactly one token everywhere in the
  frontend, and a qualified name is three.
  bug-p-a-qualified-type-name-cannot-be-a-generic-argument

  The oracle is FPC's output for this exact file. }
{$mode objfpc}
type
  generic TBox<T> = class
    V: T;
    function Get: T;
  end;

  TOuter = class
  type
    TPair = record
      K: Integer;
      L: Integer;
    end;
    TTag = record
      N: Integer;
    end;
  end;

  { A second holder, so the minted alias names cannot be confused across
    outers -- `TOuter.TPair` and `TOther.TPair` are different types with the
    same final name component, which a mint keyed only on the last component
    would silently merge. }
  TOther = class
  type
    TPair = record
      K: Integer;
    end;
  end;

  { Row 1: the plain case. }
  TB1 = specialize TBox<TOuter.TPair>;
  { Row 2: a SECOND specialization over the SAME qualified type. The alias is
    minted once per compilation, so a second emission would be a duplicate type
    declaration -- this row is what catches that. }
  TB2 = specialize TBox<TOuter.TPair>;
  { Row 3: same last component, different outer. }
  TB3 = specialize TBox<TOther.TPair>;
  { Row 4: a different nested type of the same outer. }
  TB4 = specialize TBox<TOuter.TTag>;
  { Row 5: an ordinary unqualified argument must STILL work unchanged -- the
    normalisation is meant to be invisible to every other argument shape. }
  TB5 = specialize TBox<Integer>;

function TBox.Get: T;
begin
  Result := V;
end;

var
  b1: TB1;
  b2: TB2;
  b3: TB3;
  b4: TB4;
  b5: TB5;
  nok: Integer;

procedure Chk(const what: AnsiString; got, want: Integer);
begin
  if got = want then
  begin
    writeln('ok   ', what);
    Inc(nok);
  end
  else
    writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  nok := 0;
  b1 := TB1.Create; b1.V.K := 11; b1.V.L := 12;
  b2 := TB2.Create; b2.V.K := 21; b2.V.L := 22;
  b3 := TB3.Create; b3.V.K := 31;
  b4 := TB4.Create; b4.V.N := 41;
  b5 := TB5.Create; b5.V := 51;
  Chk('qualified argument, two fields', b1.Get.K * 100 + b1.Get.L, 1112);
  Chk('the same qualified type again', b2.Get.K * 100 + b2.Get.L, 2122);
  Chk('same last component, other outer', b3.Get.K, 31);
  Chk('a second nested type of one outer', b4.Get.N, 41);
  Chk('an unqualified argument still works', b5.Get, 51);
  writeln('total ok ', nok, ' / 5');
end.
