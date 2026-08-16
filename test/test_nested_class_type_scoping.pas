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
  bug-a-duplicate-class-name-check-is-scope-blind

  Extended 2026-08-16 with the OUT-OF-LINE method implementation header
  (`function touter.tinner.Tag: string;`), which took exactly one qualifier and
  was a parse error, and with a doubly-nested class, which the type-reference
  and constructor paths also handled to only one level. Each nested class
  returns its OWN tag: that is what proves the qualifier picks the right class
  rather than merely parsing.
  bug-p-a-nested-class-method-implementation-takes-only-one-qualifier }
{$mode delphi}

type
  touter = class
  type
    tinner = class
      x: Integer;
      function Tag: string;
    end;
  end;

  tother = class
  type
    tinner = class
      w: Integer;
      v: Integer;
      function Tag: string;
    end;
  end;

  { two levels of nesting: every qualifier but the last is a scope }
  tthree = class
  type
    tmid = class
    type
      tleaf = class
        n: Integer;
        function Tag: string;
      end;
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

{ the spelling this ticket is about — resolved against the nested registry, not
  a flat namespace, so the two `tinner` bodies stay distinct }
function touter.tinner.Tag: string; begin Result := 'outer'; end;
function tother.tinner.Tag: string; begin Result := 'other'; end;
function tthree.tmid.tleaf.Tag: string; begin Result := 'leaf'; end;

var
  okc, total: Integer;
  a: touter.tinner;
  b: tother.tinner;
  f: tfwd.tstub;
  g: tthree.tmid.tleaf;

procedure ChkS(const nm, got, want: string);
begin
  Inc(total);
  if got = want then begin Inc(okc); WriteLn('ok ', nm); end
  else WriteLn('FAIL ', nm, ' got ', got, ' want ', want);
end;

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

  { the out-of-line bodies land on the right class — same method name, two
    same-named nested classes, each must answer with its own tag }
  ChkS('outer-tag', a.Tag, 'outer');
  ChkS('other-tag', b.Tag, 'other');

  { and the whole chain works two levels down }
  g := tthree.tmid.tleaf.Create;
  g.n := 55;
  Chk('leaf-field', g.n, 55);
  ChkS('leaf-tag', g.Tag, 'leaf');

  a.Free; b.Free; f.Free; g.Free;
  WriteLn('total ok ', okc, ' / ', total);
end.
