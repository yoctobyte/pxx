program Maze;
{ Seeded maze generator + BFS solver, ASCII over stdout/serial.

  Track B demo. Exercises: the lib RNG (lib/rtl/random, seeded -> reproducible),
  2-D arrays, recursion (recursive-backtracker carve), an explicit BFS queue,
  and managed-string rendering (lib/rtl/strutils IntToStr). Integer-deterministic:
  a fixed seed yields a fixed maze and a fixed solution path length.

  Deliberately uses a boolean visited-grid (not a runtime `set`) to avoid the
  set-from-runtime gap (feature-language-gaps-from-demos Gap 1); the set lane is
  a separate exercise, not this demo's point. }

uses random, strutils;

const
  MW = 12;            { cells wide }
  MH = 8;             { cells high }
  GW = 2 * MW + 1;    { render grid width  (walls between cells) }
  GH = 2 * MH + 1;    { render grid height }

type
  TCharGrid = array[0..GH - 1, 0..GW - 1] of Char;
  TBoolGrid = array[0..MH - 1, 0..MW - 1] of Boolean;
  TIntGrid  = array[0..MH - 1, 0..MW - 1] of Integer;

const
  DX: array[0..3] of Integer = (1, -1, 0, 0);
  DY: array[0..3] of Integer = (0, 0, 1, -1);

var
  grid:    TCharGrid;
  visited: TBoolGrid;

{ ---- generation: recursive backtracker ---- }

procedure Carve(cx, cy: Integer);
var i, t, d, nx, ny: Integer; order: array[0..3] of Integer;
begin
  visited[cy][cx] := True;
  { random direction order (Fisher-Yates via the lib RNG) }
  for i := 0 to 3 do order[i] := i;
  for i := 3 downto 1 do
  begin
    t := Random(i + 1);
    d := order[i]; order[i] := order[t]; order[t] := d;
  end;
  for i := 0 to 3 do
  begin
    d := order[i];
    nx := cx + DX[d];
    ny := cy + DY[d];
    if (nx >= 0) and (nx < MW) and (ny >= 0) and (ny < MH) and not visited[ny][nx] then
    begin
      { knock out the wall between (cx,cy) and (nx,ny) }
      grid[cy + ny + 1][cx + nx + 1] := ' ';
      Carve(nx, ny);
    end;
  end;
end;

procedure Generate(seed: Integer);
var r, c: Integer;
begin
  RandSeed(seed);
  for r := 0 to GH - 1 do
    for c := 0 to GW - 1 do grid[r][c] := '#';
  for r := 0 to MH - 1 do
    for c := 0 to MW - 1 do
    begin
      visited[r][c] := False;
      grid[2 * r + 1][2 * c + 1] := ' ';   { cell openings }
    end;
  Carve(0, 0);
end;

{ ---- solve: BFS over cells, mark the path ---- }

function Solve: Integer;
var
  qx, qy: array[0..MW * MH - 1] of Integer;
  px, py: TIntGrid;            { parent coords for path reconstruction }
  seen:   TBoolGrid;
  head, tail, i, d, cx, cy, nx, ny, len: Integer;
  found: Boolean;
begin
  for cy := 0 to MH - 1 do
    for cx := 0 to MW - 1 do
    begin
      seen[cy][cx] := False; px[cy][cx] := -1; py[cy][cx] := -1;
    end;

  head := 0; tail := 0;
  qx[tail] := 0; qy[tail] := 0; tail := tail + 1;
  seen[0][0] := True;
  found := False;

  while (head < tail) and not found do
  begin
    cx := qx[head]; cy := qy[head]; head := head + 1;
    if (cx = MW - 1) and (cy = MH - 1) then
    begin
      found := True;
    end
    else
      for i := 0 to 3 do
      begin
        d := i;
        nx := cx + DX[d]; ny := cy + DY[d];
        if (nx >= 0) and (nx < MW) and (ny >= 0) and (ny < MH) and not seen[ny][nx] then
          { passable only if no wall between the two cells }
          if grid[cy + ny + 1][cx + nx + 1] = ' ' then
          begin
            seen[ny][nx] := True;
            px[ny][nx] := cx; py[ny][nx] := cy;
            qx[tail] := nx; qy[tail] := ny; tail := tail + 1;
          end;
      end;
  end;

  { walk parents back from goal, marking '*' on cells and the walls between }
  len := 0;
  cx := MW - 1; cy := MH - 1;
  if seen[cy][cx] then
    while cx >= 0 do
    begin
      grid[2 * cy + 1][2 * cx + 1] := '*';
      nx := px[cy][cx]; ny := py[cy][cx];
      if nx < 0 then cx := -1            { reached the start }
      else
      begin
        grid[cy + ny + 1][cx + nx + 1] := '*';   { wall between }
        cx := nx; cy := ny;
        len := len + 1;
      end;
    end;
  Solve := len;
end;

{ ---- render ---- }

procedure Render;
var r, c: Integer; line: AnsiString;
begin
  for r := 0 to GH - 1 do
  begin
    line := '';
    for c := 0 to GW - 1 do line := line + grid[r][c];
    writeln(line);
  end;
end;

var pathLen: Integer;
begin
  Generate(12345);
  pathLen := Solve;
  Render;
  writeln('seed 12345  size ', MW, 'x', MH, '  path cells = ', IntToStr(pathLen + 1));
end.
