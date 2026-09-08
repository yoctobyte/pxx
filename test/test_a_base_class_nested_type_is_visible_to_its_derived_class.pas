program test_a_base_class_nested_type_is_visible_to_its_derived_class;
{ A BASE CLASS'S NESTED TYPE WAS INVISIBLE TO THE DERIVED CLASS, in the derived
  class's own BODY (`FAmt: TAmt`) and through the derived class's NAME
  (`var q: TDer.TAmt`). Both answered `unknown type`. fpc 3.2.2 compiles and
  runs every row here.

  THE FIX IS TWO ARMS OF AliasVisibleHere (symtab.inc): the ParsingClassBodyCi
  arm and the QualTypeOwnerCi arm now walk UClsParent, as the MethImplOwnerCi
  arm already did. All three inheritance arms walk; the one LEXICAL arm
  (UClsEnclosingCi) is untouched, and frankB's reason for keeping it exact is
  about the enclosing chain and is unaffected by this.

  THE REASON THIS FIXTURE LISTS THE KIND ON EVERY ROW, and the reason it is
  worth its length: the comment in AliasVisibleHere said, in so many words,
  "measured, the derived-BODY and qualified `TDer.TSel` spellings already
  resolved and only the implementation scope was blind." That was false, and it
  was false when written -- re-measured 2026-09-07 at HEAD and identically on
  pin v407.

  WHAT MADE IT LOOK TRUE IS THAT THE ALIAS TABLE HOLDS ONLY THREE OF THE SEVEN
  NESTED KINDS. A nested RECORD and a nested CLASS are REGISTRY rows and
  FindNestedType has walked UClsParent all along; a nested ENUM lives in a table
  with no owner column at all, so it was never scoped in the first place. Those
  three resolved and said nothing whatever about the table under test. The three
  that DO live in Alias* -- a plain alias, a subrange and a procedural type --
  were the three that failed. A probe that does not name its KIND is answering
  about a different table better than half the time, which is a positive control
  drawn from the wrong population wearing an unfamiliar hat.

  So: rows `body alias`, `body range`, `body proc`, `qual alias`, `qual range`
  and `qual proc` are the FIX -- each measured refused before it. Rows `body
  enum`, `body rec`, `body class`, `qual enum`, `qual rec`, `qual class` are the
  CONTROLS that were already right and must stay right; they are exactly the
  rows whose passing produced the false claim, so a fixture without them would
  reproduce the mistake it is documenting. `base alias` and `base range` are the
  OWNING-class control: the fix must not be paid for by breaking the spelling
  that always worked.

  ONE KIND IS DELIBERATELY ABSENT. `var q: TDer.TArr` -- a nested named ARRAY in
  a qualified DECLARATION -- is still refused, and it is NOT this defect:
  `TBase.TArr` is refused identically, so it has nothing to do with inheritance.
  Filed as bug-p-a-nested-array-type-is-refused-in-a-qualified-declaration. The
  UNQUALIFIED body spelling `FArr: TArr` is here and passes, which is what says
  the two are separate.

  bug-p-a-base-class-nested-type-resolves-but-cannot-be-assigned-or-called }
{$mode delphi}
type
  TBase = class
  public type
    TAmt = Integer;
    TRng = 1..9;
    TEn  = (eA, eB, eC);
    TArr = array[0..2] of Integer;
    TRec = record x: Integer; end;
    TIn  = class class function Tag: Integer; end;
    TSel = function(a: Integer): Integer of object;
  end;

  TDer = class(TBase)
    FAmt: TAmt;
    FRng: TRng;
    FEn : TEn;
    FArr: TArr;
    FRec: TRec;
    FIn : TIn;
    FSel: TSel;
    function Twice(a: Integer): Integer;
  end;

class function TBase.TIn.Tag: Integer; begin Tag := 77; end;
function TDer.Twice(a: Integer): Integer; begin Twice := a * 2; end;

var
  d: TDer;
  qa: TDer.TAmt; qr: TDer.TRng; qe: TDer.TEn;
  qc: TDer.TRec; qi: TDer.TIn;  qs: TDer.TSel;
  ba: TBase.TAmt; br: TBase.TRng;
begin
  d := TDer.Create;
  d.FAmt := 1; d.FRng := 2; d.FEn := eB; d.FArr[0] := 3; d.FRec.x := 4;
  d.FIn := TDer.TIn.Create; d.FSel := d.Twice;
  qa := 11; qr := 5; qe := eC; qc.x := 12; qi := TBase.TIn.Create; qs := d.Twice;
  ba := 21; br := 6;
  WriteLn('body alias = ', d.FAmt);
  WriteLn('body range = ', Ord(d.FRng));
  WriteLn('body enum  = ', Ord(d.FEn));
  WriteLn('body array = ', d.FArr[0]);
  WriteLn('body rec   = ', d.FRec.x);
  WriteLn('body class = ', d.FIn.Tag);
  WriteLn('body proc  = ', d.FSel(10));
  WriteLn('qual alias = ', qa);
  WriteLn('qual range = ', Ord(qr));
  WriteLn('qual enum  = ', Ord(qe));
  WriteLn('qual rec   = ', qc.x);
  WriteLn('qual class = ', qi.Tag);
  WriteLn('qual proc  = ', qs(20));
  WriteLn('base alias = ', ba);
  WriteLn('base range = ', Ord(br));
end.
