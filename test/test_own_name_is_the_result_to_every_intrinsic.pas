{ A FUNCTION'S OWN NAME IS ITS RESULT VARIABLE, and thirteen intrinsics did not
  know it.

  `FindSym` cannot see the own name -- it is a PROC, not a symbol -- and the
  own-name-is-Result rule lives in the expression parser. So inside
  `function G`, `Str(7, G)` and `Val(s, G)` and `New(G)` and `Include(G, x)`
  all answered `undefined variable (G)`, while `Fill(G)` -- the SAME name to a
  user procedure's `var` parameter, in the same program -- worked, because that
  path goes through the expression parser. Two paths for one concept, and the
  second one was broken thirteen times over.

  THE RULE WAS ALREADY EXTRACTED. `OwnNameResultSym` has existed since somebody
  hit `Inc(FuncName[0])` in FPC's cutils.pas, and exactly ONE of its thirteen
  potential callers ever learned about it. The other twelve each spelled the
  same two lines -- FindSym, then ParseLValueAST -- and agreed with each other
  perfectly, which is why no reading of them could find the fact none of them
  had. The instrument for a missing caller is the callee's own contract.

  MEASURED: fpc 3.2.2 accepts the own name in all six shapes below. pxx refused
  five. Row D is the sixth, and it is the load-bearing one: `GetMem` WORKED
  before this fix, and it worked because it takes its destination through
  ParseExpr and so never had a copy of the rule to be wrong. The site with no
  copy is the site that was right.

  Row G is the shape that motivated it -- FPC's own `tstunits/erroru.pp` has a
  nested `getsize` doing exactly `Str(l, getsize); getsize := getsize + ' bytes'`,
  and that unit is the helper behind five conformance rows.

  Row H is the CONTROL for the shadowing rule: a local named like the function
  still wins, so the own-name arm must only fire when nothing else claimed the
  name. Row I is the control for the other guard: `G()` is a recursive CALL and
  a call is not an lvalue, so a following `(` must never take this arm.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_own_name_is_the_result_to_every_intrinsic;

type
  PR = ^Integer;
  TS = set of 'a'..'e';

procedure Fill(var s: string); begin s := 'user-var'; end;

function A: string;                                  { Str }
begin Str(7, A); end;

function B: Integer;                                 { Val }
var c: Integer;
begin Val('7', B, c); end;

function C: PR;                                      { New }
begin New(C); C^ := 3; end;

function D: PR;                                      { GetMem -- was already ok }
begin GetMem(D, 8); D^ := 4; end;

function E2: TS;                                     { Include }
begin E2 := []; Include(E2, 'b'); end;

function F: PR;                                      { ReallocMem }
begin GetMem(F, 8); ReallocMem(F, 16); F^ := 6; end;

function G: string;                                  { erroru.pp's own shape }

  function getsize(l: Integer): string;
  begin
    Str(l, getsize);
    getsize := getsize + ' bytes';
  end;

begin
  G := getsize(4096);
end;

function H: string;                                  { CONTROL: a local wins }
var H2: string;
begin
  H2 := 'local';
  Fill(H2);
  H := H2;
end;

function I2(n: Integer): Integer;                    { CONTROL: `(` is a call }
begin
  if n <= 0 then I2 := 0 else I2 := n + I2(n - 1);
end;

var
  s: string;

begin
  writeln('A Str            : ', A);
  writeln('B Val            : ', B);
  writeln('C New            : ', C^);
  writeln('D GetMem was ok  : ', D^);
  writeln('E Include        : ', 'b' in E2);
  writeln('F ReallocMem     : ', F^);
  writeln('G nested Str     : ', G);
  writeln('H CONTROL local  : ', H);
  writeln('I CONTROL call   : ', I2(4));
  s := '';
  Fill(s);
  writeln('J user var param : ', s);
end.
