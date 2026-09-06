{ A `var` section initialiser can hold an ADDRESS, not only an ordinal.

  `var P: Pointer = @Something` is the same grammar and the same emitter as the
  typed-CONST spelling one section over, and only the const half was wired to
  the non-ordinal value forms (@proc, @var, @TClass.Method). The var half did
  not REFUSE them: ConstEval cannot evaluate `@` and does not consume it
  either, so the declaration loop desynced and the program died with
  `expected 'begin' before '@'` -- a complaint about a var section that had
  already ended, naming a construct the source never got wrong.

  Every row reads the address BACK rather than testing it against nil: a
  zeroed slot passes a nil check, so `<> nil` cannot tell a stored address
  from a machinery that did nothing. The method row compares against the same
  `@` taken at run time for the same reason. }
program test_a_var_section_initialiser_can_hold_an_address;

type
  TProc  = procedure(n: Integer);
  TThing = class
    procedure Say(n: Integer);
  end;

procedure Emit(n: Integer);
begin
  WriteLn('emit ', n);
end;

procedure TThing.Say(n: Integer);
begin
  WriteLn('say ', n);
end;

var
  Seed: Integer = 41;

var
  GProc: TProc   = @Emit;          { @proc      }
  GAddr: PInteger = @Seed;         { @var       }
  GMeth: Pointer = @TThing.Say;    { @TClass.Method }

procedure Local;
var
  LProc: TProc    = @Emit;
  LAddr: PInteger = @Seed;
begin
  LProc(3);
  WriteLn('local reads ', LAddr^);
  LAddr^ := 55;
  WriteLn('local wrote ', Seed);
end;

begin
  GProc(1);
  WriteLn('global reads ', GAddr^);
  GAddr^ := 42;
  WriteLn('global wrote ', Seed);
  if GMeth = Pointer(@TThing.Say) then
    WriteLn('method address matches')
  else
    WriteLn('method address DIFFERS');
  Local;
  WriteLn('seed ends ', Seed);
end.
