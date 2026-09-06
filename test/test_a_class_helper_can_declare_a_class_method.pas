program test_a_class_helper_can_declare_a_class_method;
{ A CLASS HELPER'S TARGET HAS A METACLASS, AND THE RULE THAT REFUSED IT IS ABOUT
  TARGETS THAT DO NOT.

    TH = class helper for TA
      class function Other: LongInt;      -- refused with "a class method of a
                                             record must be declared static"

  `class helper for T` is parsed by the advanced-record member machinery -- a
  (No braces inside this header: the file declares objfpc, where fpc nests
  comments and merely warns, but a mode directive is part of the invocation its
  oracle must use and the next person to change the mode should not have to
  discover that. -Mdelphi/-Mtp/-Miso do not nest.)

  helper lives in the UCls tables with UClsIsRecord set -- so the record rule
  (terecs5: a record's class method must be static, because a record has no VMT
  and no class reference) fired on a helper whose TARGET is a class and DOES
  have one. fpc 3.2.2 compiles this file and prints these seven rows. The
  message also told the reader their class helper was a record, and adding
  `static` makes it compile, so the wrong diagnostic reads as advice.

  ROWS E AND F ARE THE ONES THAT COST THE MOST AND THEY ARE WHY THIS IS NOT
  THREE LINES. With the declaration accepted and the member resolved, the call
  reached the body and SEGFAULTED -- the ticket recorded it as Runtime error
  216 and parked the whole thing as a design question: what is `Self` for a
  class helper's class method, when the helper row itself has no VMT?

  It is not a design question. Delphi's answer is that Self is the class
  reference the call was SPELLED ON -- so `TA.WhoAmI` sees TA and `TD.WhoAmI`
  sees TD -- and both halves of this compiler already knew how to carry that:
  the metaclass receiver is an AN_CLASSREF over a class index, and an ordinary
  class method already types Self as `tyPointer`/REC_NONE. What was missing was
  that the helper's Self was typed as a TA INSTANCE on both the decl and impl
  sides, so the class reference passed at the call site was read as an object
  and `Self.ClassName` fetched a VMT word from inside the RTTI blob.

  ROWS C AND D SEPARATE "IT COMPILES" FROM "IT DISPATCHES": both call the same
  class method, and D goes through a DESCENDANT's name. A fix that hard-wired
  the helper's target would print 3 for both and pass, while E/F are what prove
  the receiver is the spelled class rather than a constant -- TA and TD, not TA
  twice. A row whose right answer equals what doing nothing produces cannot
  fail, and `Other` returning a literal is exactly that row.

  ROWS B AND G ARE THE INSTANCE HELPER, UNCHANGED, on the base and on the
  descendant: the instance path was already correct and is the thing a change
  to Self's type could most easily break.

  The three targets that genuinely have no metaclass -- a plain record, a
  `record helper`, a `type helper for <scalar>` -- must still be refused, and
  that is asserted separately in
  test_a_class_method_still_needs_static_where_there_is_no_metaclass.

  ORACLE: `fpc -Mobjfpc` 3.2.2's own output, byte for byte.
  bug-p-a-class-helpers-class-method-is-refused-by-the-record-metaclass-rule }
{$mode objfpc}

type
  TA = class
    function Inst: LongInt;
  end;

  TD = class(TA)
  end;

  TH = class helper for TA
    function Extra: LongInt;
    class function Other: LongInt;
    class function WhoAmI: ShortString;
  end;

function TA.Inst: LongInt;
begin
  Inst := 1;
end;

function TH.Extra: LongInt;
begin
  Extra := 2;
end;

class function TH.Other: LongInt;
begin
  Other := 3;
end;

class function TH.WhoAmI: ShortString;
begin
  WhoAmI := Self.ClassName;
end;

var
  a: TA;
  d: TD;
begin
  a := TA.Create;
  d := TD.Create;
  WriteLn('A ', a.Inst);      { the class's own method, through the helper's scope }
  WriteLn('B ', a.Extra);     { the helper's INSTANCE method — already worked }
  WriteLn('C ', TA.Other);    { the helper's CLASS method, the ticket's subject }
  WriteLn('D ', TD.Other);    { …through a descendant's name }
  WriteLn('E ', TA.WhoAmI);   { Self is the class the call was SPELLED on }
  WriteLn('F ', TD.WhoAmI);   { …and it is TD here, not TA }
  WriteLn('G ', d.Extra);     { the instance path on the descendant }
end.
