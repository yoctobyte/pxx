{ `not` over every operand shape the old node-kind whitelist ever named, plus the
  shapes it deliberately distrusted.

  `not` used to pick bitwise-vs-logical from ASTTk *and* a whitelist of operand
  node kinds "whose type is authoritative" — array element, field, deref, Ord(x),
  value-cast, nested not, and/or/xor at explicit width, arithmetic binop, unary
  minus. Every entry arrived AFTER someone shipped wrong bits: `not rb[0]`
  printed TRUE, `not ord(e)` silently corrupted a hash, `not Int64(0)` printed
  TRUE, `not -1` printed TRUE. A whitelist of the shapes someone happened to hit
  is not a rule.

  The list is gone; the operand's type decides. This file is what stops it
  growing back — each row is a shape whose ANSWER would change if the tag were
  wrong in either direction, and every value here is fpc 3.2.2's on this source.

  Read the two halves against each other: the integer rows must come back as
  complements, the Boolean rows as flips. A regression shows up as a Boolean
  printed where a number belongs or the reverse, which is the loudest failure
  this construct produces.
  feature-a-trust-the-operand-type-for-not }
program test_not_operand_type_matrix;
{$mode objfpc}{$H+}
type TE = (eA, eB, eC);
     TR = record f: Integer; b: Boolean; end;
var i: Integer; i64: Int64; by: Byte; q1, q2: QWord;
    bo, bo2: Boolean; e: TE; r: TR; ch: Char;
    arr: array[0..3] of Integer; barr: array[0..3] of Boolean;
    pi: ^Integer; pb: ^Boolean;
function FInt: Integer; begin FInt := 5; end;
function FBool: Boolean; begin FBool := True; end;
begin
  i := 5; i64 := 7; by := 3; q1 := 12; q2 := 5;
  bo := True; bo2 := False; e := eB; r.f := 4; r.b := True; ch := 'a';
  arr[0] := 6; barr[0] := True; pi := @i; pb := @bo;

  { INTEGER operands — bitwise complement }
  WriteLn(not i);            { -6 }
  WriteLn(not i64);          { -8 }
  WriteLn(not by);           { 252 — byte width }
  WriteLn(not r.f);          { field }
  WriteLn(not arr[0]);       { array element }
  WriteLn(not pi^);          { deref }
  WriteLn(not FInt);         { call with an integer return type }
  WriteLn(not Ord(e));       { Ord — an integer by definition }
  WriteLn(not Ord(ch));      { ...complemented at the OPERAND's width }
  WriteLn(not Int64(0));     { ordinal value-cast }
  WriteLn(not -1);           { unary minus }
  WriteLn(not (i - 1));      { arithmetic binop }
  WriteLn(not (i shr 1));    { shift — `shr` lexes as an identifier }
  WriteLn(not (i and 3));    { integer and/or/xor }
  WriteLn(not (i or 3));
  WriteLn(not (i xor 3));
  WriteLn(not (q1 or q2));   { and/or/xor at an explicit 64-bit width }
  WriteLn(not (q1 and q2));
  WriteLn(not not i);        { a nested BITWISE not }

  { BOOLEAN operands — logical negation. These are the ones the whitelist
    existed to protect, back when the frontend tagged some of them tyInteger. }
  WriteLn(not bo);
  WriteLn(not bo2);
  WriteLn(not r.b);          { Boolean field — same node kind as `not r.f` }
  WriteLn(not barr[0]);      { Boolean array element }
  WriteLn(not pb^);          { Boolean deref }
  WriteLn(not FBool);        { Boolean-returning call }
  WriteLn(not (i = 5));      { comparison }
  WriteLn(not (i <> 5));
  WriteLn(not (i < 5));
  WriteLn(not (bo and bo2)); { logical and/or/xor }
  WriteLn(not (bo or bo2));
  WriteLn(not (bo xor bo2));
  WriteLn(not (FBool and bo));
  WriteLn(not (i + 1 = 6));  { an arithmetic binop INSIDE a comparison }
  WriteLn(not not bo);       { a nested LOGICAL not }
  WriteLn(not True);
end.
