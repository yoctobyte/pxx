{ `{$if sizeof(Extended) <> sizeof(Double)}` -- FPC's ordinary idiom for
  guarding a platform-dependent arm. The Pascal conditional evaluator had no
  `sizeof` operand, so the directive could not be answered and the file died in
  the PREPROCESSOR with `conditional directive: expected operator`, a message
  that does not contain the word sizeof.

  EVERY ROW ASSERTS A RELATION AND CARRIES NO WIDTH, deliberately. The point is
  not what `sizeof(Extended)` is -- it is that the PREPROCESSOR and the
  COMPILER give the same answer about it, which is the only property a second
  source of size truth could break. A row spelled `sizeof(Extended) = 10` would
  be a fourth name-to-width table written in the test instead of the compiler,
  it would encode one target, and it would go stale exactly the way the three
  tables BuiltinTypeNameTk's comment records did.

  IT IS ALSO WHY THIS FILE DOES NOT COMPARE ITSELF TO FPC. pxx's `Extended` is
  eight bytes and FPC's is ten, so fpc takes the `differ` branch and we take
  the `same` branch -- from the same source, both correctly, about two
  different compilers' representations. Asserting fpc's BRANCH here would
  assert fpc's Extended, which is not ours and is not a goal. Asserting the
  AGREEMENT is target-independent and is the actual claim.

  ROW_RECORD is the positive control. A record's width is its layout and a
  layout does not exist during LexAll, where conditionals are resolved -- so
  the operand must produce a DIAGNOSTIC NAMING THE TYPE, never a default. A
  conditional that takes the wrong branch does not produce a wrong value; it
  produces a different program, which is why answering 0 or a pointer width
  here would be worse than refusing.
  bug-p-the-conditional-evaluator-cannot-answer-sizeof-so-eleven-corpus-rows-die-in-the-preprocessor }
program test_the_conditional_evaluator_can_answer_sizeof;

{$IFDEF ROW_RECORD}
type TRec = record a, b: Integer; end;
{$ENDIF}

const
{$if sizeof(Double) = sizeof(Extended)}
  PP_DOUBLE_IS_EXTENDED = True;
{$else}
  PP_DOUBLE_IS_EXTENDED = False;
{$endif}

{$if sizeof(Integer) < sizeof(Int64)}
  PP_INT_UNDER_INT64 = True;
{$else}
  PP_INT_UNDER_INT64 = False;
{$endif}

{$if sizeof(Char) = 1}
  PP_CHAR_IS_ONE = True;
{$else}
  PP_CHAR_IS_ONE = False;
{$endif}

{$if sizeof(Pointer) = sizeof(NativeInt)}
  PP_PTR_IS_NATIVEINT = True;
{$else}
  PP_PTR_IS_NATIVEINT = False;
{$endif}

{ Both operands constant, so this row also proves the value reached the INT
  stack rather than being coerced to a boolean: `8 and TRUE` is a loud type-mix
  error in this evaluator, and a sizeof pushed as a bool would trip it. }
{$if (sizeof(Int64) = 8) and (sizeof(SmallInt) = 2)}
  PP_MIXED_AND = True;
{$else}
  PP_MIXED_AND = False;
{$endif}

{$IFDEF ROW_RECORD}
{ Must not compile: a record cannot be sized at directive-evaluation time. }
{$if sizeof(TRec) > 4}
  PP_REC = 1;
{$else}
  PP_REC = 0;
{$endif}
{$ENDIF}

var fails: Integer;

procedure Chk(const what: string; pp, rt: Boolean);
begin
  if pp <> rt then
  begin
    WriteLn('FAIL ', what, ' preprocessor=', pp, ' compiler=', rt);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  Chk('Double = Extended',    PP_DOUBLE_IS_EXTENDED, SizeOf(Double)  = SizeOf(Extended));
  Chk('Integer < Int64',      PP_INT_UNDER_INT64,    SizeOf(Integer) < SizeOf(Int64));
  Chk('Char = 1',             PP_CHAR_IS_ONE,        SizeOf(Char)    = 1);
  Chk('Pointer = NativeInt',  PP_PTR_IS_NATIVEINT,   SizeOf(Pointer) = SizeOf(NativeInt));
  Chk('int stack, not bool',  PP_MIXED_AND,
      (SizeOf(Int64) = 8) and (SizeOf(SmallInt) = 2));
  WriteLn('fails=', fails);
  WriteLn('CONDSIZEOF OK');
end.
