{ Test material for bug-p-uses-order-does-not-decide-which-unit-wins: two units
  exporting the same routine names, so a `uses` clause has to decide. Legal
  Pascal, which FPC accepts silently — the LAST unit in the clause wins. }
unit shadow_a;
interface
function Who: AnsiString;             { parameterless: binds via FindProcBound }
function WhoP(x: Integer): AnsiString; { with args: binds via MatchProcCall }
implementation
function Who: AnsiString;
begin Who := 'A'; end;
function WhoP(x: Integer): AnsiString;
begin WhoP := 'A'; end;
end.
