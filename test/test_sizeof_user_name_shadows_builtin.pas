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

  NOT asserted here, deliberately: `SizeOf(v)` where v is a user RECORD variable
  answers 8 rather than 12 on this compiler, before and after this fix. That is
  a separate and older defect with its own ticket; baking 8 in here would freeze
  it, and baking 12 in would make this test fail for a reason it is not about. }

type
  Currency  = record a, b, c: Integer; end;   { shadows the builtin float name }
  TDateTime = array[0..9] of Byte;            { shadows the builtin alias      }
  Comp      = (cOne, cTwo, cThree);           { shadows the builtin Int64 name }

var
  longbool: Boolean;      { a VARIABLE whose name is a builtin type }
  wordbool: Char;
  variant:  Int64;

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

  longbool := True; wordbool := 'x'; variant := 5;
  WriteLn('i ', longbool, ' ', wordbool, ' ', variant);
end.
