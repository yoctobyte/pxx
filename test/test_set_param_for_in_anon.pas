{ The ANONYMOUS-set spelling of a set parameter: `procedure P(const q: set of TM)`.

  Split out of test_set_param_for_in.pas deliberately, and the reason is the
  point of the file: THERE IS NO FPC ORACLE FOR THIS ROW. fpc 3.2.2 refuses an
  anonymous set type in a parameter list outright --
    a5.pas(4,22) Error: Type identifier expected
    a5.pas(4,22) Fatal: Syntax error, ")" expected but "SET" found
  -- so the expected output here is OURS by construction, not a match against
  another compiler. We accept what fpc rejects, which is not a defect
  (CLAUDE.md: "Us accepting what FPC rejects is not a defect").

  Keeping it in the sibling file would have cost that file its oracle for all
  seven of its other rows, since fpc could not have built the program at all.

  What it still pins: the same symbol stamp the named spelling needs. The
  element identity is captured under `if tk = tySet`, which is a KIND test and
  not a named-type test, so the anonymous spelling goes down the same path --
  and if someone ever narrows that guard to named set types, this is the row
  that says so. }
program test_set_param_for_in_anon;
type
  TM = (mA, mB, mC);

procedure PEnumAnon(const q: set of TM);
var m: TM;
begin
  Write('enum anon   : ');
  for m in q do Write(Ord(m), ' ');
  WriteLn;
end;

procedure PCharAnon(const q: set of Char);
var c: Char;
begin
  Write('char anon   : ');
  for c in q do Write(c);
  WriteLn;
end;

begin
  PEnumAnon([mA, mC]);
  PCharAnon(['a', 'c']);
end.
