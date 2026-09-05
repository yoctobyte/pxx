{ A generic parameter CONSTRAINT is not a type body.

  DGenDeclAnchor walks from a mode-Delphi template to a use of it, counting
  class/record/interface/object body depth, and anchors the minted alias after
  the last depth-0 `;`. A LATER template's parameter list put a real tkClass or
  tkRecord token in that path -- `TBoxB<T: class>`, `TRecB<T: record>` -- and
  each opens nothing and has no `end`, so the earlier template's walk was left
  permanently one deep per constraint crossed. Same consequence as `of object`
  (see test_delphi_generic_of_object_anchor.pas): the walk runs past the section
  it exists to stop at and anchors the alias inside a routine body.

  `<T: constructor>` did NOT reproduce, because `constructor` reaches a
  different arm of the same walk. The three spellings are one concept, so the
  fix skips the whole `< ... >` group rather than special-casing each keyword,
  and arm 3 covers the third spelling to keep it that way.

  ARM 5 IS THE CONTROL FOR THE FIX'S OWN RISK, and it is drawn from the
  population the fix could break rather than the one it repairs: a real
  anonymous `record ... end` FIELD between the template and the use, a genuine
  body whose `;` must still be hidden from the anchor. It is aimed at the
  tempting wrong fix -- stop counting tkRecord, since a constraint's `record`
  reaches that arm -- and it catches it. MEASURED, not assumed: with
  `tkRecord` never counted, arm 5 fails and reports

      pascal26:125: error: expected ':'
        near: : Integer ; end ; TBox5$TLate5 >>>  specialize TBox5

  the alias spliced into the record. What arm 5 does NOT control for is the
  skipper being too WIDE about what it calls a `< ... >` group: nothing in this
  file contains a `<` that is not one, so a widened skip passes every arm here.
  That guard lives in DGenAngleGroupEnd's own token filter and is stated there
  rather than tested here, which is worth knowing before trusting this file to
  cover a change to it.

  Arms 4 and 6 are the negative controls: an UNCONSTRAINED later template, and a
  use with no later template at all, both of which always worked. Without them a
  green run cannot tell this fix from a coincidence.

  Verified against fpc 3.2.2, which prints this file's .expected.
  bug-p-a-generic-parameter-constraint-is-counted-as-a-type-body }
program test_delphi_generic_constraint_anchor;
{$MODE DELPHI}
type
  TArg = class end;
  TArgRec = record F: Integer; end;

{ 1: a later template constrained with `class` }
type
  TBox1<T: class> = class
    class function Who: Integer;
  end;
  TLater1<T: class> = class
    class function Who: Integer;
  end;
  TLate1 = class end;
class function TBox1<T>.Who: Integer; begin Result := 1; end;
class function TLater1<T>.Who: Integer; begin Result := 11; end;
function Use1: Integer;
var a: TBox1<TLate1>; b: TLater1<TLate1>;
begin
  a := nil; b := nil;
  if (a = nil) and (b = nil) then Use1 := TBox1<TLate1>.Who else Use1 := 0;
end;

{ 2: a later template constrained with `record` }
type
  TBox2<T: class> = class
    class function Who: Integer;
  end;
  TLater2<T: record> = class
    class function Who: Integer;
  end;
  TLate2 = class end;
class function TBox2<T>.Who: Integer; begin Result := 2; end;
class function TLater2<T>.Who: Integer; begin Result := 22; end;
function Use2: Integer;
var a: TBox2<TLate2>; b: TLater2<TArgRec>;
begin
  a := nil;
  if a = nil then Use2 := TBox2<TLate2>.Who else Use2 := 0;
end;

{ 3: a later template constrained with `constructor` -- the spelling that did
     NOT reproduce, kept so the three stay one concept }
type
  TBox3<T: class> = class
    class function Who: Integer;
  end;
  TLater3<T: constructor> = class
    class function Who: Integer;
  end;
  TLate3 = class
    constructor Create;
  end;
constructor TLate3.Create; begin end;
class function TBox3<T>.Who: Integer; begin Result := 3; end;
class function TLater3<T>.Who: Integer; begin Result := 33; end;
function Use3: Integer;
var a: TBox3<TLate3>;
begin
  a := nil;
  if a = nil then Use3 := TBox3<TLate3>.Who else Use3 := 0;
end;

{ 4: NEGATIVE CONTROL -- the later template is UNCONSTRAINED }
type
  TBox4<T: class> = class
    class function Who: Integer;
  end;
  TLater4<T> = class
    class function Who: Integer;
  end;
  TLate4 = class end;
class function TBox4<T>.Who: Integer; begin Result := 4; end;
class function TLater4<T>.Who: Integer; begin Result := 44; end;
function Use4: Integer;
var a: TBox4<TLate4>;
begin
  a := nil;
  if a = nil then Use4 := TBox4<TLate4>.Who else Use4 := 0;
end;

{ 5: CONTROL FOR THE FIX'S OWN RISK -- a real anonymous `record ... end` field
     between template and use. Its body must STILL be counted, or the `;`
     between A and B becomes a candidate anchor. }
type
  TBox5<T: class> = class
    class function Who: Integer;
  end;
  THolder5 = class
    F: record
         A: Integer;
         B: Integer;
       end;
  end;
  TLate5 = class end;
class function TBox5<T>.Who: Integer; begin Result := 5; end;
function Use5: Integer;
var a: TBox5<TLate5>; h: THolder5;
begin
  a := nil; h := nil;
  if (a = nil) and (h = nil) then Use5 := TBox5<TLate5>.Who else Use5 := 0;
end;

{ 6: NEGATIVE CONTROL -- no later template at all }
type
  TBox6<T: class> = class
    class function Who: Integer;
  end;
  TLate6 = class end;
class function TBox6<T>.Who: Integer; begin Result := 6; end;
function Use6: Integer;
var a: TBox6<TLate6>;
begin
  a := nil;
  if a = nil then Use6 := TBox6<TLate6>.Who else Use6 := 0;
end;

begin
  WriteLn('arm1 ', Use1);
  WriteLn('arm2 ', Use2);
  WriteLn('arm3 ', Use3);
  WriteLn('arm4 ', Use4);
  WriteLn('arm5 ', Use5);
  WriteLn('arm6 ', Use6);
end.
