program SudokuSolver;
{ Constraint backtracking Sudoku solver. Candidate sets are integer bitmasks
  (bit v set = value v present among a cell's peers) — `set of 1..9` cannot be
  built from runtime values in this dialect yet (Include/Exclude + variable set
  elements unimplemented), and the ticket explicitly allows a bitmask word.
  Pure integer + managed-string parse/render: a deterministic cross-target oracle. }

type
  TGrid = array[0..80] of Integer;

var
  puzzles: array[0..2] of AnsiString;
  g: TGrid;
  i: Integer;

procedure Parse(const s: AnsiString; var grid: TGrid);
var k: Integer; c: Char;
begin
  for k := 0 to 80 do
  begin
    c := s[k + 1];
    if (c >= '1') and (c <= '9') then
      grid[k] := Ord(c) - Ord('0')
    else
      grid[k] := 0;
  end;
end;

function UsedMask(const grid: TGrid; cell: Integer): Integer;
{ Bits of the values already present in the cell's row, column and 3x3 box. }
var r, c, br, bc, rr, cc, k, mask: Integer;
begin
  r := cell div 9;
  c := cell mod 9;
  mask := 0;
  for k := 0 to 8 do
  begin
    mask := mask or (1 shl grid[r * 9 + k]);   { row }
    mask := mask or (1 shl grid[k * 9 + c]);    { column }
  end;
  br := (r div 3) * 3;
  bc := (c div 3) * 3;
  for rr := 0 to 2 do
    for cc := 0 to 2 do
      mask := mask or (1 shl grid[(br + rr) * 9 + (bc + cc)]);
  UsedMask := mask;
end;

function Solve(var grid: TGrid): Boolean;
{ Backtracking with the minimum-remaining-values heuristic: always branch on the
  empty cell with the fewest candidates. Keeps even pathological "hardest"
  puzzles near-instant — fast enough under qemu on every target. }
var k, v, mask, cnt, bestCell, bestCnt, bestMask: Integer; found: Boolean;
begin
  bestCell := -1; bestCnt := 99; bestMask := 0;
  for k := 0 to 80 do
  begin
    if grid[k] = 0 then
    begin
      mask := UsedMask(grid, k);
      cnt := 0;
      for v := 1 to 9 do
        if (mask and (1 shl v)) = 0 then cnt := cnt + 1;
      if cnt < bestCnt then
      begin
        bestCnt := cnt; bestCell := k; bestMask := mask;
      end;
    end;
  end;
  if bestCell < 0 then
  begin
    Solve := True;          { no empty cell -> solved }
    Exit;
  end;
  found := False;
  for v := 1 to 9 do
  begin
    if not found and ((bestMask and (1 shl v)) = 0) then
    begin
      grid[bestCell] := v;
      if Solve(grid) then found := True
      else grid[bestCell] := 0;
    end;
  end;
  Solve := found;
end;

procedure Render(const grid: TGrid);
var k: Integer; line: AnsiString;
begin
  line := '';
  for k := 0 to 80 do
    line := line + Chr(Ord('0') + grid[k]);
  writeln(line);
end;

begin
  puzzles[0] := '53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79';
  puzzles[0] := puzzles[0] + '.';
  puzzles[1] := '..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9';
  puzzles[1] := puzzles[1] + '.';
  puzzles[2] := '8..........36......7..9.2...5...7.......457.....1...3...1....68..85...1..9....4..';
  puzzles[2] := puzzles[2] + '.';
  for i := 0 to 2 do
  begin
    Parse(puzzles[i], g);
    if Solve(g) then Render(g)
    else writeln('no solution');
  end;
end.
