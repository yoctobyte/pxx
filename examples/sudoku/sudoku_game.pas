program SudokuGame;
{ Interactive Sudoku: a puzzle generator plus a line-oriented console UI.

  Companion to sudoku.pas (the fixed-oracle solver). This one *makes* puzzles
  and lets a human play them. It is deliberately "platonic": pure integer +
  managed-string + readln/writeln, no ANSI escapes, no cursor control, no
  external library. That keeps it identical on a desktop terminal and on an
  ESP32 serial console (line in, line out — that is all the device offers).

  Dialect notes (same constraints as sudoku.pas):
    - Candidate sets are integer bitmasks; `set of 1..9` from runtime values is
      not buildable in this dialect yet.
    - A small linear-congruential PRNG is carried in a global; there is no RTL
      Random() dependency, so output is reproducible from a seed.

  Commands (one per line):
    r c v   place value v (1..9) at row r, col c (1..9); v=0 clears the cell
    h       hint: fill one empty cell from the solution
    s       solve: reveal the whole solution
    n       new puzzle (next seed)
    p       print the board again
    q       quit
}

const
  REMOVE_TARGET = 48;   { cells to dig out; higher = harder }

type
  TGrid = array[0..80] of Integer;

var
  puzzle:   TGrid;      { current playable board (0 = empty)        }
  solution: TGrid;      { the unique full solution                  }
  given:    array[0..80] of Boolean;  { true = clue, cannot edit    }
  rngState: Cardinal;   { PRNG state                                }
  seed:     Cardinal;   { seed of the current puzzle                }

{ ---- PRNG: 31-bit linear congruential, app-local and reproducible ---- }

function NextRand(n: Integer): Integer;
{ Returns a value in 0..n-1. }
begin
  rngState := (rngState * 1103515245 + 12345) and $7FFFFFFF;
  NextRand := Integer(rngState mod Cardinal(n));
end;

{ ---- Constraint helpers (shared shape with sudoku.pas) ---- }

function UsedMask(const grid: TGrid; cell: Integer): Integer;
{ Bits of values already present in the cell's row, column and 3x3 box. }
var r, c, br, bc, rr, cc, k, mask: Integer;
begin
  r := cell div 9;
  c := cell mod 9;
  mask := 0;
  for k := 0 to 8 do
  begin
    mask := mask or (1 shl grid[r * 9 + k]);
    mask := mask or (1 shl grid[k * 9 + c]);
  end;
  br := (r div 3) * 3;
  bc := (c div 3) * 3;
  for rr := 0 to 2 do
    for cc := 0 to 2 do
      mask := mask or (1 shl grid[(br + rr) * 9 + (bc + cc)]);
  UsedMask := mask;
end;

function FirstEmpty(const grid: TGrid): Integer;
{ Lowest-index empty cell, or -1 if the grid is full. }
var k: Integer;
begin
  FirstEmpty := -1;
  for k := 0 to 80 do
    if grid[k] = 0 then
    begin
      FirstEmpty := k;
      Exit;
    end;
end;

{ ---- Generation ---- }

function FillFull(var grid: TGrid): Boolean;
{ Backtracking fill that tries candidates in a random order, so each run
  produces a different complete, valid grid. }
var cell, mask, i, v, t, n: Integer;
    order: array[0..8] of Integer;
    done: Boolean;
begin
  cell := FirstEmpty(grid);
  if cell < 0 then
  begin
    FillFull := True;
    Exit;
  end;

  { collect legal candidates for this cell }
  mask := UsedMask(grid, cell);
  n := 0;
  for v := 1 to 9 do
    if (mask and (1 shl v)) = 0 then
    begin
      order[n] := v;
      n := n + 1;
    end;

  { Fisher-Yates shuffle of the candidate list }
  for i := n - 1 downto 1 do
  begin
    t := NextRand(i + 1);
    v := order[i]; order[i] := order[t]; order[t] := v;
  end;

  done := False;
  for i := 0 to n - 1 do
    if not done then
    begin
      grid[cell] := order[i];
      if FillFull(grid) then done := True
      else grid[cell] := 0;
    end;
  FillFull := done;
end;

function CountSolutions(var grid: TGrid; limit: Integer): Integer;
{ Counts solutions up to `limit` (we only ever care whether it is exactly 1).
  Restores every cell it touches, so `grid` is unchanged on return. }
var cell, mask, v, total: Integer;
begin
  cell := FirstEmpty(grid);
  if cell < 0 then
  begin
    CountSolutions := 1;
    Exit;
  end;
  mask := UsedMask(grid, cell);
  total := 0;
  for v := 1 to 9 do
    if (total < limit) and ((mask and (1 shl v)) = 0) then
    begin
      grid[cell] := v;
      total := total + CountSolutions(grid, limit - total);
      grid[cell] := 0;
    end;
  CountSolutions := total;
end;

procedure Generate;
{ Build a full solution, then dig holes while the puzzle stays uniquely
  solvable. The order of holes is randomized so puzzles vary by seed. }
var k, t, c, saved: Integer;
    order: array[0..80] of Integer;
    removed: Integer;
begin
  rngState := seed;

  for k := 0 to 80 do puzzle[k] := 0;
  FillFull(puzzle);
  for k := 0 to 80 do solution[k] := puzzle[k];

  { shuffle the cell visiting order }
  for k := 0 to 80 do order[k] := k;
  for k := 80 downto 1 do
  begin
    t := NextRand(k + 1);
    c := order[k]; order[k] := order[t]; order[t] := c;
  end;

  removed := 0;
  for k := 0 to 80 do
    if removed < REMOVE_TARGET then
    begin
      c := order[k];
      saved := puzzle[c];
      puzzle[c] := 0;
      if CountSolutions(puzzle, 2) = 1 then
        removed := removed + 1
      else
        puzzle[c] := saved;   { removing it broke uniqueness; put it back }
    end;

  for k := 0 to 80 do
    given[k] := puzzle[k] <> 0;
end;

{ ---- Rendering (plain ASCII, serial-console safe) ---- }

procedure Render;
var r, c, k, v: Integer; line: AnsiString;
begin
  writeln('');
  writeln('    1 2 3   4 5 6   7 8 9');
  writeln('  +-------+-------+-------+');
  for r := 0 to 8 do
  begin
    line := Chr(Ord('1') + r) + ' | ';
    for c := 0 to 8 do
    begin
      k := r * 9 + c;
      v := puzzle[k];
      if v = 0 then line := line + '.'
      else line := line + Chr(Ord('0') + v);
      if (c mod 3) = 2 then line := line + ' | '
      else line := line + ' ';
    end;
    writeln(line);
    if (r mod 3) = 2 then
      writeln('  +-------+-------+-------+');
  end;
  writeln('');
end;

function IsSolved: Boolean;
var k: Integer;
begin
  IsSolved := False;
  for k := 0 to 80 do
    if puzzle[k] <> solution[k] then Exit;
  IsSolved := True;
end;

{ ---- Line tokenizer + command dispatch ---- }

function NextToken(const s: AnsiString; var pos: Integer; var tok: AnsiString): Boolean;
begin
  while (pos <= Length(s)) and (s[pos] = ' ') do pos := pos + 1;
  if pos > Length(s) then
  begin
    NextToken := False;
    Exit;
  end;
  tok := '';
  while (pos <= Length(s)) and (s[pos] <> ' ') do
  begin
    tok := tok + s[pos];
    pos := pos + 1;
  end;
  NextToken := True;
end;

procedure DoMove(const t0, line: AnsiString; var pos: Integer);
var r, c, v, cell, er, ec, ev: Integer; t1, t2: AnsiString;
begin
  Val(t0, r, er);
  if (NextToken(line, pos, t1)) then Val(t1, c, ec) else ec := 1;
  if (NextToken(line, pos, t2)) then Val(t2, v, ev) else ev := 1;

  if (er <> 0) or (ec <> 0) or (ev <> 0) then
  begin
    writeln('? need: r c v   (e.g. 3 5 7)');
    Exit;
  end;
  if (r < 1) or (r > 9) or (c < 1) or (c > 9) or (v < 0) or (v > 9) then
  begin
    writeln('? row/col 1..9, value 0..9');
    Exit;
  end;
  cell := (r - 1) * 9 + (c - 1);
  if given[cell] then
  begin
    writeln('? that cell is a fixed clue');
    Exit;
  end;
  puzzle[cell] := v;
  Render;
  if IsSolved then
    writeln('*** Solved! Type n for a new puzzle, q to quit. ***');
end;

procedure DoHint;
var cell: Integer;
begin
  cell := FirstEmpty(puzzle);
  if cell < 0 then
  begin
    writeln('Board already full.');
    Exit;
  end;
  puzzle[cell] := solution[cell];
  given[cell] := True;
  Render;
  if IsSolved then writeln('*** Solved! ***');
end;

{ ---- Main loop ---- }

var
  line, t0: AnsiString;
  pos: Integer;
  running: Boolean;

begin
  seed := 1;
  Generate;
  writeln('Sudoku. Commands: "r c v" place, h hint, s solve, n new, p print, q quit.');
  Render;

  running := True;
  while running do
  begin
    write('> ');
    readln(line);
    pos := 1;
    if NextToken(line, pos, t0) then
    begin
      if t0 = 'q' then running := False
      else if t0 = 'n' then
      begin
        seed := seed + 1;
        Generate;
        writeln('New puzzle (seed ', seed, ').');
        Render;
      end
      else if t0 = 'p' then Render
      else if t0 = 'h' then DoHint
      else if t0 = 's' then
      begin
        for pos := 0 to 80 do puzzle[pos] := solution[pos];
        Render;
        writeln('Solution shown.');
      end
      else
        DoMove(t0, line, pos);
    end;
  end;
  writeln('Bye.');
end.
