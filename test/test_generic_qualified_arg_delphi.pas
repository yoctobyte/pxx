program test_generic_qualified_arg_delphi;
{ The mode-Delphi arm of bug-p-a-qualified-type-name-cannot-be-a-generic-argument:
  `TBox<TOuter.TPair>` with no `specialize` keyword. The objfpc arm goes through
  ParseSpecialization; this one goes through DelphiRewriteGenericUses, which
  collects the `<...>` group one token per argument and simply failed to match,
  leaving the group alone -- `unknown type: TBox`.

  Oracle is FPC's output for this exact file.

  The declaration ORDER here -- TOuter FIRST -- used to be load-bearing: a
  Delphi-mode argument naming a type declared AFTER the template failed for an
  unrelated reason, because the rewrite put its alias declarations immediately
  behind the template where they could name only what was already declared.
  That was bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template,
  FIXED 2026-08-31: the alias now anchors before the declaration that USES it.
  The order is kept as written -- this file's subject is qualified NAMES, and
  the ordering case has its own file (test_delphi_generic_arg_declared_later.pas,
  seven arms) rather than being folded in here. }
{$mode delphi}
type
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

  TOther = class
  type
    TPair = record
      K: Integer;
    end;
  end;

  TBox<T> = class
    V: T;
    function Get: T;
  end;

  TB1 = TBox<TOuter.TPair>;
  { the SAME qualified type again -- the alias is minted once per compilation }
  TB2 = TBox<TOuter.TPair>;
  { same last component, different outer }
  TB3 = TBox<TOther.TPair>;
  { a different nested type of the same outer }
  TB4 = TBox<TOuter.TTag>;
  { an ordinary unqualified argument must still work unchanged }
  TB5 = TBox<Integer>;

function TBox<T>.Get: T;
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
