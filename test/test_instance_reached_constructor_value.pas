{ A constructor reached through an already-constructed INSTANCE -- `R.Create(...)`,
  not `TRec.Create(...)`. FPC re-runs the constructor on that instance and the
  expression's VALUE is the instance. pxx typed the expression from
  Procs[mpi].RetType, which for a ctor is tyInteger because a ctor's proc carries
  no return type at all, so:

    R.Create(False);           was correct -- a statement never asks for the value
    R2 := R.Create(False);     compiled and printed 20 20 against fpc's 10 20
    Show(R.Create(False));     "no overload of Show matches ... (Integer)"

  POSITIVE CONTROL, and it takes TWO runs because the refusal masks the wrong
  value. Against pin v407 (095ef4811a5b) this file does not compile at all --
  both ShowR/ShowC rows are refused -- so with those two rows removed the SAME
  pinned compiler runs it and prints

    assig 20 20     (fpc: 10 20)
    assiC 0 0       (fpc: 10 20)

  i.e. the class arm answered a zeroed record. A control that only shows the
  refusal would certify the compile fix and say nothing about the two silent
  wrong answers underneath it.

  ROW 1 IS THE REGRESSION CANARY AND IT IS NOT DECORATION: the statement form was
  the one spelling already working, and the first cut of the fix broke it --
  `(call, receiver)` in statement position was read as the start of an assignment
  and reported `expected ':=' before ';'`. Keep it first.

  Record and class rows both, because both arms were broken identically here --
  which is unusual for this area and is what pointed at the shared instance-method
  path rather than at either type's own.

  THE SELECTOR ROWS CAME SECOND AND ARE THE INTERESTING ONES. `R.Create(False).X`
  was still `IR_UNSUPPORTED ... (kind 68)` after the parser fix, because
  IRLowerAddress keeps an allow-list of node kinds whose ADDRESS it can produce
  and AN_COMMA was not on it -- the same split that routine's own comment
  records for kinds 53, 58 and 88: `r := f(x)` fine, `f(x).c` refused. Asserted
  two selectors deep as well, since one level can be satisfied by an accident
  the second would not survive.

  AND THE BARE CONSTRUCTION STATEMENT, last row: `TCls.Create(False);` with no
  destination is legal FPC and was `expected ':=' before ';'` -- AN_METACLASS_NEW
  is a construction, not one of ASTNodeIsCall's five kinds. It leaks by
  construction, which is the programmer's business and not a parse error; the
  row asserts only that it compiles and runs. fpc-testsuite texception10.pp is
  where it came from. }
program test_instance_reached_constructor_value;
{$mode delphi}
type
  TInner = record
    A: Integer;
    constructor Create(v: Integer);
  end;
  TRec = record
    X, Y: Integer;
    I: TInner;
    constructor Create(dummy: Boolean);
  end;
  TCls = class
    X, Y: Integer;
    constructor Create(dummy: Boolean);
  end;

constructor TInner.Create(v: Integer); begin A := v; end;
constructor TRec.Create(dummy: Boolean); begin X := 10; Y := 20; I.Create(7); end;
constructor TCls.Create(dummy: Boolean); begin X := 10; Y := 20; end;

procedure ShowR(R: TRec); begin Writeln('argR  ', R.X, ' ', R.Y); end;
procedure ShowC(C: TCls); begin Writeln('argC  ', C.X, ' ', C.Y); end;

var
  R, R2: TRec;
  C, C2: TCls;
begin
  R.Create(False);                 Writeln('stmt  ', R.X, ' ', R.Y);
  R2 := R.Create(False);           Writeln('assig ', R2.X, ' ', R2.Y);
  ShowR(R.Create(False));
  C := TCls.Create(False);
  C.Create(False);                 Writeln('stmtC ', C.X, ' ', C.Y);
  C2 := C.Create(False);           Writeln('assiC ', C2.X, ' ', C2.Y);
  ShowC(C.Create(False));
  Writeln('selR  ', R.Create(False).X);
  Writeln('selC  ', C.Create(False).X);
  Writeln('sel2  ', R.Create(False).I.A);   { two selectors deep }
  TCls.Create(False);
  Writeln('bare  ok');
end.
