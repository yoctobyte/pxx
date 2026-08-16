program test_nested_class_type_scoping;
{ A type declared inside a class body belongs to THAT CLASS, not to the unit.
  Every value here is FPC 3.2.2's on this same source.

  The duplicate-class-name check (added 2026-07-30) consulted a flat per-unit
  namespace, so `touter.tinner` and `tother.tinner` — two legal, distinct types
  — read as a redeclaration and legal Pascal did not compile. The same flatness
  rejected a generic's nested type on the SECOND specialization, which is
  exactly what FPC's tgeneric72 exists to assert is unique.

  The first nested type of a bare name keeps that bare name (so every existing
  unqualified use resolves as before); a later same-named one is registered
  under its qualified `Outer.Inner` and reached through the nested-type
  registry. That registry is also what makes the qualified spelling MEAN
  something: before it, `var b: tother.tinner` silently bound to touter's, and
  the wrong one simply lacked the fields.
  bug-a-duplicate-class-name-check-is-scope-blind }
{$mode delphi}

type
  touter = class
  type
    tinner = class
      x: Integer;
    end;
  end;

  tother = class
  type
    tinner = class
      w: Integer;
      v: Integer;
    end;
  end;

  { the forward-stub handling the original commit added, which was never the
    problem and must keep working }
  tfwd = class
  type
    tstub = class;
    tstub = class
      k: Integer;
    end;
  end;

var
  okc, total: Integer;
  a: touter.tinner;
  b: tother.tinner;
  f: tfwd.tstub;

procedure Chk(const nm: string; got, want: Integer);
begin
  Inc(total);
  if got = want then begin Inc(okc); WriteLn('ok ', nm); end
  else WriteLn('FAIL ', nm, ' got ', got, ' want ', want);
end;

begin
  okc := 0; total := 0;

  { each qualified name resolves to ITS OWN class — the fields prove which }
  a := touter.tinner.Create;
  a.x := 11;
  Chk('outer-field', a.x, 11);

  b := tother.tinner.Create;
  b.w := 22; b.v := 33;
  Chk('other-field-w', b.w, 22);
  Chk('other-field-v', b.v, 33);

  f := tfwd.tstub.Create;
  f.k := 44;
  Chk('forward-stub', f.k, 44);

  { they are distinct types, so the instances are distinct objects }
  Chk('distinct', Ord(TObject(a) = TObject(b)), 0);

  a.Free; b.Free; f.Free;
  WriteLn('total ok ', okc, ' / ', total);
end.
