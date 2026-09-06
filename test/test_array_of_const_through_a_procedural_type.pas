{ `array of const` in a PROCEDURAL TYPE, called indirectly.

  Replaces test_array_of_const_in_a_procedural_type_is_refused.pas, which
  asserted the refusal deliberately: the three-line parse arm was written and
  reverted TWICE because making the declaration parse turned a clean refusal
  into a silent wrong Length, and the real defect was the open-array literal
  losing its length through any procedural-type call
  (bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call,
  fixed in fe0c492d1). The refusal file said to delete rather than edit it, so
  that a reader cannot mistake an inverted assertion for the original claim.

  EVERY ROW READS AN ELEMENT AS WELL AS A LENGTH, and no row is empty. Both
  guards are load-bearing and both were learned here:

  - An EMPTY literal prints Length 0 under the broken build too, because 0 is a
    legal length -- the expected value collides with the failure value, so a
    `[]` probe passes and ships the bug.
  - Length alone cannot see a wrong element STRIDE. `VType` is read so a
    mismarshalled TVarRec vector fails rather than merely counting right.

  All four spellings, because fpc 3.2.2 accepts all four under -Mobjfpc and
  -Mdelphi: plain and `of object`, `const`-modified and bare.

  bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap }
{$mode objfpc}
program test_array_of_const_through_a_procedural_type;
type
  TPlainBare  = procedure(Args: array of const);
  TPlainConst = procedure(const Args: array of const);
  TObjBare    = procedure(Args: array of const) of object;
  TObjConst   = procedure(const Fmt: string; const Args: array of const) of object;

  TSink = class
    procedure Bare(Args: array of const);
    procedure Fmt(const F: string; const Args: array of const);
  end;

procedure FreeBare(Args: array of const);
begin
  WriteLn('freebare n=', Length(Args), ' t0=', Args[0].VType,
          ' t', Length(Args) - 1, '=', Args[Length(Args) - 1].VType);
end;

procedure FreeConst(const Args: array of const);
begin
  WriteLn('freeconst n=', Length(Args), ' t0=', Args[0].VType);
end;

procedure TSink.Bare(Args: array of const);
begin
  WriteLn('methbare n=', Length(Args), ' t0=', Args[0].VType);
end;

procedure TSink.Fmt(const F: string; const Args: array of const);
begin
  WriteLn('methfmt ', F, ' n=', Length(Args), ' t0=', Args[0].VType,
          ' t1=', Args[1].VType);
end;

var
  pb: TPlainBare;
  pc: TPlainConst;
  ob: TObjBare;
  oc: TObjConst;
  s: TSink;
begin
  pb := @FreeBare;
  pb([1, 2, 3, 'four']);

  pc := @FreeConst;
  pc(['a', 'b']);

  s := TSink.Create;

  ob := @s.Bare;
  ob([9]);

  oc := @s.Fmt;
  oc('why', [11, 'twelve']);

  { The DIRECT calls, same routines, same literals -- the control that says a
    wrong number below is the procedural type's and not the routine's. }
  FreeBare([1, 2, 3, 'four']);
  s.Fmt('direct', [11, 'twelve']);
end.
