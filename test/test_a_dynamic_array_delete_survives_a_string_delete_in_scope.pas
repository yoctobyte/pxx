{ THE GUARD ANSWERED WHETHER, NOT WHICH. SoftIntrinsicOpen asks whether any
  routine of an intrinsic's name is in scope and nothing about the call's
  arguments -- and lib/rtl/sysutils.pas declares `Delete(var s: AnsiString;
  index, count)` and `Insert(const src: AnsiString; var dst: AnsiString;
  index)`, which fpc keeps in `system` and not in sysutils. So a single
  `uses sysutils` closed the DYNAMIC-ARRAY Delete and Insert for essentially
  every program in this tree, and said so:

    error: no overload of Delete matches these arguments
      argument types: (record, Integer, Integer)
      candidates: Delete(AnsiString, Integer, Integer)

  fcl-passrc's pscanner.pp:5025 and :5033 are the live case (SetWarnMsgState on
  FWarnMsgStates, a dyn-array FIELD read through implicit Self).

  THE LAST TWO ROWS ARE THE CONTROL AND THEY ARE WHY THE FIX IS THREE
  CONDITIONS RATHER THAN ONE. A user routine named Delete that CAN take a
  dynamic array must still win -- fpc runs it (measured: fpc 3.2.2 prints
  a0=777 and leaves the length at 3) -- so the reopening consults the shadow's
  PARAMETER TYPE, not merely its existence. Both spellings are in this one file
  because they differ by scope alone: the nested Delete inside UserWins is the
  shadow that binds, and the identical call in the main body is the intrinsic.
  Two files could each print a plausible number and pass; two numbers here
  disagree on sight.

  Every row asserts a VALUE. A dyn-array Delete that did nothing at all would
  still compile clean, and a length alone cannot tell a correct Insert from a
  wrong one -- 777 and the surviving elements are what separate them.
  bug-p-a-string-delete-in-scope-closes-the-dynamic-array-delete-intrinsic }
{$mode objfpc}
program test_a_dynamic_array_delete_survives_a_string_delete_in_scope;
uses sysutils;
type
  TRec = record Number: Integer; State: Integer; end;
  TRecs = array of TRec;
  TA = array of Integer;
  TC = class
    F: TRecs;                { the pscanner.pp shape: a dyn-array FIELD }
    procedure Go;
  end;

procedure TC.Go;
var it: TRec;
begin
  SetLength(F, 3);
  F[0].Number := 10; F[1].Number := 20; F[2].Number := 30;
  Delete(F, 1, 1);                        { implicit Self, no qualifier }
  WriteLn('field  del  len=', Length(F), ' ', F[0].Number, ' ', F[1].Number);
  it.Number := 99; it.State := 7;
  Insert(it, F, 1);
  WriteLn('field  ins  len=', Length(F), ' ', F[0].Number, ' ', F[1].Number,
          ' ', F[1].State, ' ', F[2].Number);
end;

{ a nested routine that CAN bind a dynamic array: this one must win }
procedure UserWins;
var a: TA;
  procedure Delete(var x: TA; index, count: Integer);
  begin x[0] := 777; end;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  Delete(a, 1, 1);
  WriteLn('shadow wins len=', Length(a), ' a0=', a[0]);
end;

var b: TA; c: TC; s: AnsiString;
begin
  c := TC.Create; c.Go;

  SetLength(b, 3); b[0] := 1; b[1] := 2; b[2] := 3;
  Delete(b, 1, 1);
  WriteLn('local  del  len=', Length(b), ' ', b[0], ' ', b[1]);
  Insert(55, b, 1);
  WriteLn('local  ins  len=', Length(b), ' ', b[0], ' ', b[1], ' ', b[2]);

  { the string spellings must be untouched -- they still bind the shadow }
  s := 'abcdef'; Delete(s, 2, 3);   WriteLn('string del  ', s);
  s := 'abcdef'; Insert('XY', s, 2); WriteLn('string ins  ', s);

  UserWins;
end.
