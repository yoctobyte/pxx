{ `of object` derailed the mode-Delphi generic alias anchor.

  DGenDeclAnchor walks forward from a template to a use of it, tracking
  class/record/interface/object body depth, and splices the minted alias
  declaration after the last depth-0 `;`. It counted the `object` in a
  method-pointer type -- `TCb = function(x: Integer): Integer of object;` --
  as opening a type body. That `object` opens nothing, so the depth went up and
  could never come back down.

  ONE of them breaks a whole unit. With the depth stuck above zero the walk's
  `implementation` arm -- guarded on depth = 0 -- never fires, so it leaves the
  type section it exists to stop at; the routine bodies it then crosses each
  decrement on their own `end` until the count reaches 0 again somewhere in the
  middle of the implementation, where a `;` looks exactly like a declaration
  boundary. The alias was spliced BETWEEN TWO ROUTINE BODIES with no `type` in
  force. On rtl-generics' Generics.Defaults (five `of object`) that came out as
  `unexpected token in a unit implementation section` at line 1064, reported
  ~1750 lines before the use at 2819 that caused it.

  EACH ARM GETS ITS OWN TYPE SECTION, CLOSED BY THE FUNCTION THAT USES IT, and
  that is not tidiness: one shared section makes every arm's walk cross every
  later arm's declarations, so the arms mask each other and a failure cannot be
  attributed to the shape it names. Measured -- as one section, arm 5 failed for
  arm 6's reasons.

  ARM 3 IS THE ONE THAT MATTERS FOR THE FIX. Arms 1-2 also pass if `object` is
  simply never counted, which would be the wrong fix: a real `TOld = object ...
  end` IS a type body, and not counting it makes every `;` between its fields a
  candidate anchor. Arm 3 puts a real object type between the template and the
  use, so it fails under the lazy fix and under the original bug alike. The
  discriminator is the preceding token, not the word.

  ARM 2 IS THE NEGATIVE CONTROL: the identical declaration with `of object`
  removed always compiled, so a run of arm 1 alone could not tell this fix from
  a coincidence.

  The `unit` row is the corpus shape proper -- the use sits in a routine body in
  a unit's IMPLEMENTATION, which is the only place the original diagnostic could
  be produced.

  Verified against fpc 3.2.2, which prints this file's .expected.
  bug-p-a-method-pointer-type-derails-the-delphi-generic-alias-anchor }
program test_delphi_generic_of_object_anchor;
{$MODE DELPHI}
uses dgen_of_object_unit;

type
  TArg = class end;

function Drain: Integer;
begin
  Result := 0;
end;

{ 1: a method-pointer type between the template and the use }
type
  TBox1<T: class> = class
    class function Who: Integer;
  end;
  TCb1 = function(x: Integer): Integer of object;
  TCb1b = procedure(x: Integer) of object;
class function TBox1<T>.Who: Integer; begin Result := 1; end;
function Use1: Integer;
var b: TBox1<TArg>;
begin
  b := nil;
  if b = nil then Use1 := TBox1<TArg>.Who else Use1 := Drain;
end;

{ 2: NEGATIVE CONTROL -- the same procedural type without `of object` }
type
  TBox2<T: class> = class
    class function Who: Integer;
  end;
  TCb2 = function(x: Integer): Integer;
class function TBox2<T>.Who: Integer; begin Result := 2; end;
function Use2: Integer;
var b: TBox2<TArg>;
begin
  b := nil;
  if b = nil then Use2 := TBox2<TArg>.Who else Use2 := Drain;
end;

{ 3: a REAL `object` type body between template and use -- must STILL be
     counted, or the `;` between its fields becomes a candidate anchor }
type
  TBox3<T: class> = class
    class function Who: Integer;
  end;
  TOld3 = object
    F: Integer;
    G: Integer;
  end;
class function TBox3<T>.Who: Integer; begin Result := 3; end;
function Use3: Integer;
var b: TBox3<TArg>; o: TOld3; n: Integer;
begin
  b := nil; o.F := 0; o.G := 0;
  n := o.F + o.G;
  if (b = nil) and (n = 0) then Use3 := TBox3<TArg>.Who else Use3 := Drain;
end;

{ 4: both -- a real object body AND a method-pointer type, so the walk must
     tell them apart rather than pick one rule }
type
  TBox4<T: class> = class
    class function Who: Integer;
  end;
  TOld4 = object
    F: Integer;
  end;
  TCb4 = function(x: Integer): Integer of object;
class function TBox4<T>.Who: Integer; begin Result := 4; end;
function Use4: Integer;
var b: TBox4<TArg>; o: TOld4;
begin
  b := nil; o.F := 0;
  if (b = nil) and (o.F = 0) then Use4 := TBox4<TArg>.Who else Use4 := Drain;
end;

{ 5: `of object` as a CLASS FIELD's type, so the derailing token sits inside a
     body that is itself counted }
type
  TBox5<T: class> = class
    class function Who: Integer;
  end;
  THolder5 = class
    FCb: function(x: Integer): Integer of object;
  end;
class function TBox5<T>.Who: Integer; begin Result := 5; end;
function Use5: Integer;
var b: TBox5<TArg>;
begin
  b := nil;
  if b = nil then Use5 := TBox5<TArg>.Who else Use5 := Drain;
end;

begin
  WriteLn('arm1 ', Use1);
  WriteLn('arm2 ', Use2);
  WriteLn('arm3 ', Use3);
  WriteLn('arm4 ', Use4);
  WriteLn('arm5 ', Use5);
  WriteLn('unit ', dgen_of_object_unit.UUser.GetIt);
end.
