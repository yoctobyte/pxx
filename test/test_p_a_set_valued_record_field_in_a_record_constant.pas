{ A SET-VALUED FIELD IN A RECORD CONSTANT, which is how FPC's own tokens.pas
  writes its ~400-row token table:

      arraytokeninfo : ttokenarray = (
        (str:'' ;special:true ;keyword:[m_none];op:NOTOKEN), ...

  It was refused with `expected field name in record constant` POINTING AT THE
  `[`, which is a message about the wrong thing: the field name was fine, and
  ConstEval simply cannot evaluate a set and does not CONSUME one either, so the
  field loop came back round with TokPos still on the value. TryParseInitValForm
  exists to stop exactly that, and the set arm was the one form written out by
  hand in the const-ARRAY element loop and given to no other caller.

  THE THREE SLOTS ARE THE TEST, because the gap was never "sets do not work" --
  a set-typed const array HAS worked since
  bug-p-a-const-array-of-sets-is-rejected-as-too-many-elements. Only some slots
  had the arm:
    `tbl`      a set field inside a const array of records   -- REFUSED before
    `solo`   a set field in a scalar record constant       -- REFUSED before
    `v`        a var initialiser of set type                 -- REFUSED before,
               with a different message again (`expected 'begin' before '['`),
               which is why it read as a separate bug and is not one.
  A fixture asserting only the first would pass on a fix that reached one caller.

  THE EMPTY SET IS ITS OWN ROW. `[]` is the value a token table spends most of
  its rows on, and it is the one value that cannot be told from "nothing was
  written": a slot the machinery never touched reads as the empty set too. So
  `miss` asserts a NON-empty set in a neighbouring row of the same array -- if
  the bake did nothing, `miss` goes FALSE and the row fails.

  THE IDENT FORM IS DELIBERATELY NOT ASSERTED HERE, and the reason is a
  measurement: fpc 3.2.2 REFUSES a named set constant in either slot --
  `keyword: both` inside a record constant and `var v: tsws = both` both answer
  `Illegal expression`. pxx accepts both, which CLAUDE.md classes as not a
  defect, so the arm exists and has no differential row it could ever have. A
  fixture that asserted it would be asserting against no oracle.
  `both` stays as a plain scalar set constant so the row still reads something
  the ident path produced.

  POSITIVE CONTROL, verified: the PINNED compiler refuses this file at the first
  table row -- `expected field name in record constant`.
  Expected output is fpc 3.2.2's for this exact source.
  bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant }
program test_p_a_set_valued_record_field_in_a_record_constant;
{$mode objfpc}{$H+}

type
  tsw  = (m_none, m_objfpc, m_delphi);
  tsws = set of tsw;
  trec = record
    str: string[4];
    special: boolean;
    keyword: tsws;
    op: Integer;
  end;

const
  both: tsws = [m_objfpc, m_delphi];

  tbl: array[0..2] of trec = (
    (str:'';    special:true;  keyword:[m_none];            op:0),
    (str:'+';   special:false; keyword:[m_objfpc, m_delphi]; op:1),
    (str:'end'; special:true;  keyword:[];                  op:2));

  solo: trec = (str:'s'; special:false; keyword:[m_objfpc, m_delphi]; op:9);

var
  v: tsws = [m_delphi];

procedure Show(const tag: AnsiString; const s: tsws);
begin
  Write(tag, ' ');
  if m_none   in s then Write('n') else Write('.');
  if m_objfpc in s then Write('o') else Write('.');
  if m_delphi in s then Write('d') else Write('.');
  WriteLn;
end;

begin
  Show('row0  ', tbl[0].keyword);
  Show('row1  ', tbl[1].keyword);
  Show('row2  ', tbl[2].keyword);
  Show('solo  ', solo.keyword);
  Show('v     ', v);
  Show('both  ', both);
  { The neighbouring-row control for the empty set: row2 is `[]` and row1 is
    not, so "the bake did nothing" cannot pass both. }
  WriteLn('miss   ', (m_objfpc in tbl[1].keyword) and not (m_objfpc in tbl[2].keyword));
  WriteLn('fields ', tbl[1].str, ' ', tbl[1].special, ' ', tbl[2].op, ' ', solo.str, ' ', solo.op);
end.
