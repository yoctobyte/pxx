program SATDemo;
{ Deterministic oracle for the sat unit (Track B).

  Solves a bundled set of DIMACS CNF instances: satisfiable ones (model verified
  by substitution via CheckModel) and classic UNSAT pigeonhole instances. The
  decision order is fixed, so SAT/UNSAT verdicts and printed models are
  byte-identical across targets. Ends 'ALL OK' iff every verdict + model check
  matches expectation -- the line make lib-test asserts. }

uses sat, sysutils;

var
  ok: Boolean;

function ResStr(r: TSatResult): AnsiString;
begin
  if r = srSat then Result := 'SAT' else Result := 'UNSAT';
end;

{ Solve src, expect verdict 'want'; if SAT, also verify the model satisfies it. }
procedure Run(const name, src, want: AnsiString);
var model: TIntArray; r: TSatResult; verdict: AnsiString;
begin
  LoadDIMACS(src);
  r := Solve(model);
  verdict := ResStr(r);
  write(name, ': ', verdict, ' (', VarCount, ' vars, ', ClauseCount, ' clauses)');
  if verdict <> want then
  begin
    ok := False;
    write('  FAIL: want ', want);
  end
  else if r = srSat then
  begin
    if CheckModel(model) then write('  [model ok]')
    else begin ok := False; write('  FAIL: model does not satisfy'); end;
  end;
  writeln;
end;

var
  php32, php43: AnsiString;
begin
  ok := True;

  { trivially SAT }
  Run('unit  ', 'p cnf 1 1' + #10 + '1 0' + #10, 'SAT');

  { (x1 v x2) ^ (~x1 v x3) ^ (~x2 v ~x3) -- SAT }
  Run('sat3  ', 'c sample' + #10 + 'p cnf 3 3' + #10 +
                '1 2 0' + #10 + '-1 3 0' + #10 + '-2 -3 0' + #10, 'SAT');

  { needs unit propagation: (x1) ^ (~x1 v x2) ^ (~x2 v x3) -> x1=x2=x3=true }
  Run('chain ', 'p cnf 3 3' + #10 + '1 0' + #10 + '-1 2 0' + #10 + '-2 3 0' + #10, 'SAT');

  { (x1 v x2) ^ (~x1) ^ (~x2) -- UNSAT }
  Run('unsat2', 'p cnf 2 3' + #10 + '1 2 0' + #10 + '-1 0' + #10 + '-2 0' + #10, 'UNSAT');

  { Pigeonhole PHP(3,2): 3 pigeons, 2 holes -- UNSAT.
    vars: p(i,h) = (i-1)*2 + h, i=1..3, h=1..2 }
  php32 :=
    'c PHP(3,2)' + #10 + 'p cnf 6 9' + #10 +
    '1 2 0' + #10 + '3 4 0' + #10 + '5 6 0' + #10 +        { each pigeon in a hole }
    '-1 -3 0' + #10 + '-1 -5 0' + #10 + '-3 -5 0' + #10 +  { hole 1: no two pigeons }
    '-2 -4 0' + #10 + '-2 -6 0' + #10 + '-4 -6 0' + #10;   { hole 2: no two pigeons }
  Run('php32 ', php32, 'UNSAT');

  { Pigeonhole PHP(4,3): 4 pigeons, 3 holes -- UNSAT.
    vars: p(i,h) = (i-1)*3 + h, i=1..4, h=1..3 }
  php43 :=
    'c PHP(4,3)' + #10 + 'p cnf 12 22' + #10 +
    '1 2 3 0' + #10 + '4 5 6 0' + #10 + '7 8 9 0' + #10 + '10 11 12 0' + #10 +
    { hole 1: vars 1,4,7,10 } '-1 -4 0' + #10 + '-1 -7 0' + #10 + '-1 -10 0' + #10 +
    '-4 -7 0' + #10 + '-4 -10 0' + #10 + '-7 -10 0' + #10 +
    { hole 2: vars 2,5,8,11 } '-2 -5 0' + #10 + '-2 -8 0' + #10 + '-2 -11 0' + #10 +
    '-5 -8 0' + #10 + '-5 -11 0' + #10 + '-8 -11 0' + #10 +
    { hole 3: vars 3,6,9,12 } '-3 -6 0' + #10 + '-3 -9 0' + #10 + '-3 -12 0' + #10 +
    '-6 -9 0' + #10 + '-6 -12 0' + #10 + '-9 -12 0' + #10;
  Run('php43 ', php43, 'UNSAT');

  writeln;
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.
