program test_sizeof_user_name_shadows_builtin;
{ A USER declaration must win over a builtin type NAME in SizeOf.

  SizeOf consults BuiltinTypeNameTk first and only reaches the
  record/alias/array/enum/variable tables in its `else`. That was harmless while
  the builtin table was a strict subset that happened to exclude the shadowable
  names; it stopped being harmless when the table was merged with the
  declaration path's, and three sizes silently changed under programs that had
  not:

      SizeOf(Currency) on a user record   12 -> 8
      SizeOf(longbool) on a Boolean var    1 -> 4
      SizeOf(tdatetime) on a 10-byte array 10 -> 8

  Wrong sizes feeding GetMem and Move, with no diagnostic. The table's own
  header already told callers to consult a user alias FIRST; SizeOf is a caller
  for which it matters and did not.
  bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts

  EVERY name below is one the builtin table KNOWS, which is the whole point —
  a shadowing test using names the table has never heard of cannot fail. That is
  also why the earlier accept-side audit of 37 builtin names could not catch
  this: a control set drawn only from builtins cannot detect a change that
  widens which names the builtin table claims.

  Checked against FPC 3.2.2 ({$MODE OBJFPC}{$H+}): identical output.

  The DECLARATION side (rows j..m) was the second half and is now fixed too.
  ParseTypeKind guarded its builtin-name chain with `FindTypeAlias(lo) >= 0`
  alone, while the SizeOf site above consults six tables -- the same predicate
  in two places, one narrow, which is the second path that stays broken. So an
  ALIAS beat a builtin name and a RECORD did not:

      SizeOf(Currency)  12 in an expression, 8 inside an array bound, SAME
                        program, ten lines apart -- self-inconsistent, so it
                        needs no oracle to be obviously wrong
      var v: Currency;  `v.a := 1` refused outright with
                        "a value of this type has no members"

  This file's earlier revision recorded row j as deliberately NOT asserted,
  because `SizeOf(v)` on a user record variable answered 8 both before and after
  that fix. That is the defect now closed, so the row is asserted rather than
  described. bug-p-a-user-type-whose-name-shadows-a-builtin-is-unusable

  NO EXPECTED VALUE BELOW IS 4 OR 8 WHERE IT COULD BE A DEFAULT. The sizes that
  matter here are 12, 10 and 6, none of which a fallback produces; 8 appears
  only in the control rows, where it is the answer being guarded rather than
  the answer under test. A row expecting the same number the broken path
  returns cannot fail. }

type
  Currency  = record a, b, c: Integer; end;   { shadows the builtin float name }
  TDateTime = array[0..9] of Byte;            { shadows the builtin alias      }
  Comp      = (cOne, cTwo, cThree);           { shadows the builtin Int64 name }
  TCurArr   = array[0..SizeOf(Currency) - 1] of Byte;  { the const-eval path }
  { The three builtin names SizeOf reaches through ParseTypeKind rather
    than through the kind table, because a capacity / a record id / a
    pointee is not a function of a TTypeKind. That delegation is a SECOND
    route into the builtin answer, so it needs its own shadowing row --
    the rows above cannot reach it, and a user declaration losing to a
    builtin on exactly these three names is what it would look like.
    14/18/22 for the same reason as 12/10/6 above: not 4, not 8, and not
    the builtin widths (256, 4128, 8) either, so no fallback prints them.
    bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size }
  ShortString = array[0..13] of Byte;   { shadows the CAPACITY-carrying name }
  TextFile    = array[0..17] of Byte;   { shadows the RECORD-carrying name   }
  PChar       = array[0..21] of Byte;   { shadows a POINTEE-carrying name    }

var
  longbool: Boolean;      { a VARIABLE whose name is a builtin type }
  wordbool: Char;
  variant:  Int64;
  wc: WideChar;           { CONTROL: an unshadowed builtin still resolves }
  bb: ByteBool;
  cv: Currency;           { a VARIABLE of the shadowing record type }
  dv: TDateTime;          { ...and of the shadowing array type    }
  av: TCurArr;
  chk: Integer;

begin
  { user TYPE names beat the builtin table }
  WriteLn('a ', SizeOf(Currency));    { the record: 12, not the builtin 8 }
  WriteLn('b ', SizeOf(TDateTime));   { the array: 10, not the builtin 8  }
  WriteLn('c ', SizeOf(Comp) > 0);    { an enum, not the builtin Int64    }

  { user VARIABLE names beat the builtin table }
  WriteLn('d ', SizeOf(longbool));    { Boolean: 1, not LongBool's 4 }
  WriteLn('e ', SizeOf(wordbool));    { Char: 1, not WordBool's 2    }
  WriteLn('f ', SizeOf(variant));     { Int64: 8, and Variant is 16  }

  { THE CONTROL, and it has to use names this file does NOT shadow. The obvious
    version — asserting SizeOf(LongBool) is still 4 — is not a control at all:
    `longbool` is a variable here, so that name now MEANS the variable and 4 is
    the wrong answer. FPC agrees, which is how this was caught. A control drawn
    from the shadowed set re-measures the rows above instead of guarding them.

    These rows are what a fix that simply stopped consulting the builtin table
    would break, and nothing above would notice. }
  WriteLn('g ', SizeOf(Cardinal), ' ', SizeOf(Int64), ' ', SizeOf(WideChar));
  WriteLn('h ', SizeOf(Integer), ' ', SizeOf(Double), ' ', SizeOf(Pointer));
  WriteLn('o ', SizeOf(ShortString), ' ', SizeOf(TextFile), ' ', SizeOf(PChar));

  longbool := True; wordbool := 'x'; variant := 5;
  WriteLn('i ', longbool, ' ', wordbool, ' ', variant);

  { THE DECLARATION SIDE. A name the builtin table knows must resolve to the
    user's type when the program declares one -- as a variable's type, and in
    a constant expression. }
  cv.a := 1; cv.b := 2; cv.c := 3;      { refused outright before the fix }
  WriteLn('j ', SizeOf(cv));            { the record: 12, not the builtin 8 }
  WriteLn('k ', cv.a + cv.b + cv.c);    { 6 -- the members exist at all }
  WriteLn('l ', SizeOf(av), ' ', Length(av));   { 12 12, not 8 8 }
  WriteLn('m ', SizeOf(dv));            { the array: 10, not the builtin 8 }

  { ...and the control for THIS half: a builtin name the program does NOT
    shadow must still resolve to the builtin when used as a variable's type.
    This is the row that goes missing, and the one a fix that simply stopped
    consulting the builtin table would break while every row above still
    passed. WideChar (2) and ByteBool (1) are chosen because no fallback in
    this area produces 2 or 1. }
  WriteLn('n ', SizeOf(wc), ' ', SizeOf(bb));

  { ASSERT, do not only PRINT. Rows a..i predate this and are judged by
    comparing the transcript against FPC by hand, which is why they are bare
    WriteLns. That is fine for a row a human reads once; it is not fine for a
    regression guard, because testmgr reads the EXIT CODE and a file that
    prints a wrong number and exits 0 cannot fail in the dimension the harness
    reads. The rows added with the ParseTypeKind fix therefore check
    themselves. No `.expected` is stored: row h prints SizeOf(Pointer), so the
    correct transcript differs per target. }
  chk := 0;
  if SizeOf(cv) <> 12 then begin WriteLn('FAIL j ', SizeOf(cv)); chk := chk + 1; end;
  if cv.a + cv.b + cv.c <> 6 then begin WriteLn('FAIL k'); chk := chk + 1; end;
  if (SizeOf(av) <> 12) or (Length(av) <> 12) then begin WriteLn('FAIL l ', SizeOf(av), ' ', Length(av)); chk := chk + 1; end;
  if SizeOf(dv) <> 10 then begin WriteLn('FAIL m ', SizeOf(dv)); chk := chk + 1; end;
  { the control: an unshadowed builtin must STILL resolve to the builtin }
  if SizeOf(wc) <> 2 then begin WriteLn('FAIL n WideChar ', SizeOf(wc)); chk := chk + 1; end;
  if SizeOf(bb) <> 1 then begin WriteLn('FAIL n ByteBool ', SizeOf(bb)); chk := chk + 1; end;
  Halt(chk);
end.
