{ SPDX-License-Identifier: 0BSD }
unit g2048;
{ 2048 engine — pure game logic, no UI. A global 4x4 grid (0 = empty, else a
  power of two). The merge logic lives in SlideLine (one 4-cell compress+merge)
  so it is exhaustively testable apart from the board; Move2048 applies it along
  rows/columns. ClearBoard/PutTile let tests build deterministic positions. }

interface

uses random;

const
  WIN_TILE = 2048;

type
  TLine = array[0..3] of Integer;

{ pure: slide a 4-cell line toward index 0 (compress, then merge equal neighbours
  once each); writes the result to outp, returns the merge score. }
function SlideLine(const inp: TLine; var outp: TLine): Integer;

procedure NewGame2048(seed: Integer);
function Move2048(dir: Integer): Boolean;   { 0=left 1=right 2=up 3=down; true if board changed }
function Score2048: Integer;
function HasWon2048: Boolean;
function IsOver2048: Boolean;
function CellAt(r, c: Integer): Integer;

{ setup / test helpers }
procedure ClearBoard;
procedure PutTile(r, c, v: Integer);

implementation

var
  grid: array[0..3, 0..3] of Integer;
  score: Integer;
  won: Boolean;

function SlideLine(const inp: TLine; var outp: TLine): Integer;
var vals: TLine; n, i, j, sc: Integer;
begin
  for i := 0 to 3 do begin vals[i] := 0; outp[i] := 0; end;
  n := 0;
  for i := 0 to 3 do
    if inp[i] <> 0 then begin vals[n] := inp[i]; n := n + 1; end;
  sc := 0; i := 0; j := 0;
  while i < n do
  begin
    if (i + 1 < n) and (vals[i] = vals[i + 1]) then
    begin
      outp[j] := vals[i] * 2;
      sc := sc + outp[j];
      i := i + 2;
    end
    else
    begin
      outp[j] := vals[i];
      i := i + 1;
    end;
    j := j + 1;
  end;
  SlideLine := sc;
end;

function CellAt(r, c: Integer): Integer;
begin
  CellAt := grid[r][c];
end;

function Score2048: Integer;
begin
  Score2048 := score;
end;

function HasWon2048: Boolean;
begin
  HasWon2048 := won;
end;

procedure ClearBoard;
var r, c: Integer;
begin
  for r := 0 to 3 do
    for c := 0 to 3 do grid[r][c] := 0;
end;

procedure PutTile(r, c, v: Integer);
begin
  grid[r][c] := v;
end;

{ map a slide line (idx, position k along the slide direction) to grid coords }
function GetCell(dir, idx, k: Integer): Integer;
begin
  case dir of
    0: GetCell := grid[idx][k];
    1: GetCell := grid[idx][3 - k];
    2: GetCell := grid[k][idx];
  else GetCell := grid[3 - k][idx];
  end;
end;

procedure SetCell(dir, idx, k, v: Integer);
begin
  case dir of
    0: grid[idx][k] := v;
    1: grid[idx][3 - k] := v;
    2: grid[k][idx] := v;
  else grid[3 - k][idx] := v;
  end;
end;

procedure SpawnTile;
var empties, i, r, c, pick, v: Integer;
begin
  empties := 0;
  for r := 0 to 3 do
    for c := 0 to 3 do
      if grid[r][c] = 0 then empties := empties + 1;
  if empties = 0 then Exit;
  pick := Random(empties);
  if Random(10) = 0 then v := 4 else v := 2;
  i := 0;
  for r := 0 to 3 do
    for c := 0 to 3 do
      if grid[r][c] = 0 then
      begin
        if i = pick then grid[r][c] := v;
        i := i + 1;
      end;
end;

function Reached2048: Boolean;
var r, c: Integer;
begin
  Reached2048 := False;
  for r := 0 to 3 do
    for c := 0 to 3 do
      if grid[r][c] >= WIN_TILE then Reached2048 := True;
end;

procedure NewGame2048(seed: Integer);
begin
  RandSeed(LongWord(seed));
  ClearBoard;
  score := 0;
  won := False;
  SpawnTile;
  SpawnTile;
end;

function Move2048(dir: Integer): Boolean;
var idx, k, total: Integer; line, res: TLine; changed: Boolean;
begin
  changed := False; total := 0;
  for idx := 0 to 3 do
  begin
    for k := 0 to 3 do line[k] := GetCell(dir, idx, k);
    total := total + SlideLine(line, res);
    for k := 0 to 3 do
    begin
      if res[k] <> line[k] then changed := True;
      SetCell(dir, idx, k, res[k]);
    end;
  end;
  if changed then
  begin
    score := score + total;
    SpawnTile;
    if Reached2048 then won := True;
  end;
  Move2048 := changed;
end;

function IsOver2048: Boolean;
var r, c, v: Integer; stuck: Boolean;
begin
  stuck := True;
  for r := 0 to 3 do
    for c := 0 to 3 do
    begin
      v := grid[r][c];
      if v = 0 then stuck := False
      else
      begin
        if (c < 3) and (grid[r][c + 1] = v) then stuck := False;
        if (r < 3) and (grid[r + 1][c] = v) then stuck := False;
      end;
    end;
  IsOver2048 := stuck;
end;

end.
