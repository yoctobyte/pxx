unit sat;

{ A small CNF-SAT solver: DIMACS parser + DPLL search (unit propagation via
  forced-literal recursion + backtracking). Our own unit, no FPC equivalent.

  Representation:
  - A literal is a signed 1-based variable index: `+v` = v, `-v` = not v.
  - The formula is a flat literal array plus clause-start offsets: clause i is
    `gLits[gClauseStart[i] .. gClauseStart[i+1]-1]`.
  - An assignment is a tri-state Integer array indexed by variable: 0 =
    unassigned, +1 = true, -1 = false (index 0 unused).

  Like the zlib unit, formula + working state are kept as MODULE GLOBALS rather
  than in a record. The stable compiler mishandles dynamic arrays stored in
  records (see bug-dynarray-in-record-corrupt), and globals also avoid threading
  arrays through several parameter layers. Consequence: the unit holds one
  formula at a time and is not reentrant -- which matches single-threaded RTL
  usage. Sets are deliberately avoided (runtime-built `set of` is a known gap).

  Decision order is deterministic (lowest unassigned variable, true first), so a
  returned model is byte-identical across targets. }

interface

type
  TSatResult = (srUnsat, srSat);
  TIntArray  = array of Integer;

{ Load a DIMACS CNF document into the module state. Lines starting with 'c' are
  comments; a 'p cnf V C' header is optional (var count is taken as the max
  variable seen). Literals are whitespace-separated ints, each clause ends in 0. }
procedure LoadDIMACS(const s: AnsiString);

function VarCount: Integer;
function ClauseCount: Integer;

{ Solve the loaded formula. On srSat, model[1..VarCount] holds +1/-1 per var. }
function Solve(var model: TIntArray): TSatResult;

{ Verify a model satisfies every loaded clause (oracle self-check). }
function CheckModel(const model: TIntArray): Boolean;

implementation

var
  gNumVars:     Integer;
  gNumClauses:  Integer;
  gLits:        TIntArray;     { all clause literals, concatenated }
  gClauseStart: TIntArray;     { length gNumClauses+1 }
  gAssign:      TIntArray;     { working assignment, size gNumVars+1 }

{ ---- DIMACS parsing ---- }

procedure LoadDIMACS(const s: AnsiString);
var
  i, n, sign, val, maxVar, litCount, clauseCount: Integer;
  c: Char;
  inComment, haveNum: Boolean;
begin
  SetLength(gLits, 0);
  SetLength(gClauseStart, 1);
  gClauseStart[0] := 0;

  n := Length(s);
  i := 1;
  maxVar := 0;
  litCount := 0;
  clauseCount := 0;
  inComment := False;

  while i <= n do
  begin
    c := s[i];

    if inComment then
    begin
      if (c = #10) or (c = #13) then inComment := False;
      i := i + 1;
      Continue;
    end;

    { 'c' comment or 'p' header line: skip to end of line }
    if (c = 'c') or (c = 'p') then
    begin
      inComment := True;
      i := i + 1;
      Continue;
    end;

    if (c = ' ') or (c = #9) or (c = #10) or (c = #13) then
    begin
      i := i + 1;
      Continue;
    end;

    { signed integer token }
    sign := 1;
    if c = '-' then begin sign := -1; i := i + 1; end
    else if c = '+' then i := i + 1;

    val := 0;
    haveNum := False;
    while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      val := val * 10 + (Ord(s[i]) - Ord('0'));
      haveNum := True;
      i := i + 1;
    end;
    if not haveNum then begin i := i + 1; Continue; end;

    val := val * sign;

    if val = 0 then
    begin
      clauseCount := clauseCount + 1;
      SetLength(gClauseStart, clauseCount + 1);
      gClauseStart[clauseCount] := litCount;
    end
    else
    begin
      SetLength(gLits, litCount + 1);
      gLits[litCount] := val;
      litCount := litCount + 1;
      if val > 0 then
      begin
        if val > maxVar then maxVar := val;
      end
      else if -val > maxVar then maxVar := -val;
    end;
  end;

  gNumVars := maxVar;
  gNumClauses := clauseCount;
end;

function VarCount: Integer;
begin
  Result := gNumVars;
end;

function ClauseCount: Integer;
begin
  Result := gNumClauses;
end;

{ ---- DPLL ---- }

{ Status of clause ci under gAssign: +1 satisfied, 0 unresolved, -1 conflict
  (all literals assigned false). When unresolved, unitVar/unitVal/unitCount
  report the unassigned literals; unitCount=1 means a forced (unit) literal. }
function ClauseStatus(ci: Integer; var unitVar, unitVal, unitCount: Integer): Integer;
var k, lit, v, av: Integer;
begin
  unitCount := 0;
  unitVar := 0;
  unitVal := 0;
  for k := gClauseStart[ci] to gClauseStart[ci + 1] - 1 do
  begin
    lit := gLits[k];
    if lit > 0 then v := lit else v := -lit;
    av := gAssign[v];
    if av = 0 then
    begin
      unitCount := unitCount + 1;
      unitVar := v;
      if lit > 0 then unitVal := 1 else unitVal := -1;
    end
    else if ((lit > 0) and (av = 1)) or ((lit < 0) and (av = -1)) then
    begin
      Result := 1;
      Exit;
    end;
  end;
  if unitCount = 0 then Result := -1 else Result := 0;
end;

{ Backtracking search over gAssign. Unit propagation emerges from preferring a
  forced literal (single-value recursion) over a free decision (two-value).
  A local snapshot restores gAssign on backtrack -- no array is passed as a
  parameter. }
function DPLL: Boolean;
var
  pre: TIntArray;
  ci, st, uVar, uVal, uCnt, v, val, i: Integer;
  conflict, allSat, foundUnit: Boolean;
begin
  conflict := False;
  allSat := True;
  foundUnit := False;
  v := 0;
  val := 0;

  for ci := 0 to gNumClauses - 1 do
  begin
    st := ClauseStatus(ci, uVar, uVal, uCnt);
    if st = -1 then begin conflict := True; Break; end
    else if st = 0 then
    begin
      allSat := False;
      if (uCnt = 1) and (not foundUnit) then
      begin
        foundUnit := True;
        v := uVar;
        val := uVal;
      end;
    end;
  end;

  if conflict then begin Result := False; Exit; end;
  if allSat then begin Result := True; Exit; end;

  SetLength(pre, gNumVars + 1);
  for i := 0 to gNumVars do pre[i] := gAssign[i];

  if foundUnit then
  begin
    gAssign[v] := val;
    if DPLL then begin Result := True; Exit; end;
    for i := 0 to gNumVars do gAssign[i] := pre[i];
    Result := False;
    Exit;
  end;

  { free decision: lowest unassigned variable, true first }
  for i := 1 to gNumVars do
    if gAssign[i] = 0 then begin v := i; Break; end;

  gAssign[v] := 1;
  if DPLL then begin Result := True; Exit; end;
  for i := 0 to gNumVars do gAssign[i] := pre[i];

  gAssign[v] := -1;
  if DPLL then begin Result := True; Exit; end;
  for i := 0 to gNumVars do gAssign[i] := pre[i];

  Result := False;
end;

function Solve(var model: TIntArray): TSatResult;
var i: Integer;
begin
  SetLength(gAssign, gNumVars + 1);
  for i := 0 to gNumVars do gAssign[i] := 0;

  if DPLL then
  begin
    SetLength(model, gNumVars + 1);
    for i := 0 to gNumVars do
    begin
      if gAssign[i] = 0 then model[i] := 1 else model[i] := gAssign[i];  { free var -> true }
    end;
    Result := srSat;
  end
  else
    Result := srUnsat;
end;

function CheckModel(const model: TIntArray): Boolean;
var ci, k, lit, v: Integer; sat: Boolean;
begin
  for ci := 0 to gNumClauses - 1 do
  begin
    sat := False;
    for k := gClauseStart[ci] to gClauseStart[ci + 1] - 1 do
    begin
      lit := gLits[k];
      if lit > 0 then v := lit else v := -lit;
      if ((lit > 0) and (model[v] = 1)) or ((lit < 0) and (model[v] = -1)) then
      begin
        sat := True;
        Break;
      end;
    end;
    if not sat then begin Result := False; Exit; end;
  end;
  Result := True;
end;

end.
