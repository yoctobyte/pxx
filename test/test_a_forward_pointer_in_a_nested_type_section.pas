program test_a_forward_pointer_in_a_nested_type_section;
{$mode objfpc}
{ A forward `^T` inside a CLASS's or RECORD's nested `type` section, where T is
  declared further down that same section.

  Until 2026-09-09 this resolved for a nested CLASS, RECORD, ARRAY or ENUM target
  and was refused for a nested plain ALIAS, POINTER alias or SUBRANGE --
  `forward type not resolved: PB` -- while the identical declarations at UNIT
  level compiled. Five kinds passing and three failing is a per-table shape, not
  a per-construct one: the drain asked FindNestedType (class-like only) and then
  the FLAT FindTypeAlias, which filters through AliasVisibleHere and therefore
  reads ParsingClassBodyCi -- and the drain runs at the unit's closing `end.`
  where that is -1. Every arm answered correctly about a scope that was not the
  row's. The record/array/enum kinds only passed because IsRecordType,
  FindArrayType and FindEnumType carry no owner column and are asked UNSCOPED.

  THE ORDER IS THE DISCRIMINATOR AND THAT IS WHY THE ORDER ROWS ARE HERE: the
  same three declarations with `PRec` written BEFORE `PPRec` compiled throughout,
  so a probe that happened to declare them in that order measured nothing. Both
  orders are asserted.

  Every row is oracled against fpc 3.2.2 -Mobjfpc, which prints the same values.
  bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved }
type
  TInClass = class
  private type
    PPRec = ^PRec;                              { forward to a POINTER ALIAS }
    PRec  = ^TRec;                              { forward to a RECORD }
    TRec  = packed record a: LongInt; end;
    PSub  = ^TSub;                              { forward to a SUBRANGE }
    TSub  = 0..99;
    PSca  = ^TSca;                              { forward to a SCALAR ALIAS }
    TSca  = LongInt;
    PEnum = ^TEnum;                             { forward to an ENUM -- passed before }
    TEnum = (eOne, eTwo);
    PArr  = ^TArr;                              { forward to an ARRAY -- passed before }
    TArr  = array[0..1] of LongInt;
  public
    class function Chain: LongInt; static;      { the two-level deref, the corpus shape }
    class function Others: LongInt; static;
  end;

  { A RECORD's nested type section is the same scope question and a separate
    parse path. fpc 3.2.2 refuses `type` inside a record in objfpc, so this half
    has no fpc oracle -- accepting what fpc rejects is not a defect, and the row
    is here to keep the two paths from drifting, not as a parity claim. }
  TInRecord = record
    type
      PPI = ^PI;
      PI  = ^TI;
      TI  = packed record a: LongInt; end;
    class function Chain: LongInt; static;
  end;

class function TInClass.Chain: LongInt;
var r: TRec; p: PRec; pp: PPRec;
begin r.a := 7; p := @r; pp := @p; Result := pp^^.a; end;

class function TInClass.Others: LongInt;
var s: TSub; ps: PSub; c: TSca; pc: PSca; e: TEnum; pe: PEnum; ar: TArr; pa: PArr;
begin
  s := 3; ps := @s;
  c := 5; pc := @c;
  e := eTwo; pe := @e;
  ar[0] := 9; pa := @ar;
  Result := ps^ + pc^ + Ord(pe^) + pa^[0];      { 3 + 5 + 1 + 9 }
end;

class function TInRecord.Chain: LongInt;
var i: TI; p: PI; pp: PPI;
begin i.a := 11; p := @i; pp := @p; Result := pp^^.a; end;

begin
  WriteLn('class-chain  ', TInClass.Chain);     { 7 }
  WriteLn('class-others ', TInClass.Others);    { 18 }
  WriteLn('record-chain ', TInRecord.Chain);    { 11 }
end.
