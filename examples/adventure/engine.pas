{ =====================================================================
  ESCAPE FROM THE MACHINE — engine unit.

  Real unit (interface/implementation) so the demo also exercises the
  unit system. The main program (adventure.pas) is thin.

  Iteration 3 adds: NPCs with dialogue + gifts, monster RIDDLE BANKS with
  random selection (own xorshift PRNG — to be swapped for the real
  random-library when it lands), and hidden exits revealed by casting XOR.

  Language surface deliberately exercised — see EXPECTED-FAILURES.md for
  exactly where the compiler is predicted to choke. Per project policy:
  missing features get implemented, the game is not dumbed down.
  ===================================================================== }

unit Engine;

interface

type
  TDirection = (dirNorth, dirSouth, dirEast, dirWest, dirUp, dirDown);
  TSpell     = (spNop, spJmp, spXor, spAnd, spOr, spHalt);
  TSpellSet  = set of TSpell;

  TItem = record
    Id, Name, Desc: AnsiString;
  end;

  TExit = record
    Dir: TDirection;
    Target: AnsiString;
    KeyItem: AnsiString;
    Hidden: Boolean;        { revealed by casting XOR in the room }
  end;

  TRiddle = record
    Q, A: AnsiString;
  end;

  { base guardian — fights from a bank of riddles, RoundsNeeded correct to win }
  TMonster = class
    Id, Name, Art, Desc, Needs: AnsiString;
    Riddles: array of TRiddle;     { the bank }
    RoundsNeeded: Integer;         { correct answers to defeat (0 => all) }
    Progress: Integer;             { correct so far this attempt }
    CurIdx: Integer;               { riddle currently posed }
    Asking: Boolean;
    RewardKind, RewardArg: AnsiString;
    Defeated: Boolean;
    function Fight(const guess: AnsiString): Boolean; virtual;
    function Taunt: AnsiString; virtual;
  end;

  { final boss — overrides the taunt (inheritance + virtual dispatch) }
  TBoss = class(TMonster)
    function Taunt: AnsiString; override;
  end;

  { a talkable character: dialogue lines + an optional gift }
  TNpc = class
    Id, Name, Art, Desc: AnsiString;
    Lines: array of AnsiString;
    Gift, GiftText, Needs: AnsiString;
    Given: Boolean;
  end;

  TRoom = class
    Id, Name, Art, Desc: AnsiString;
    Exits: array of TExit;
    Items: array of AnsiString;
    MonsterId, NpcId: AnsiString;
    WinItem: AnsiString;
    Visited: Boolean;
  end;

  TPlayer = class
  private
    function GetAlive: Boolean;
  public
    RoomId: AnsiString;
    Inventory: array of TItem;
    Spells: TSpellSet;
    Energy: Integer;
    property Alive: Boolean read GetAlive;
  end;

  TGame = class
    Rooms: array of TRoom;
    Catalog: array of TItem;
    Monsters: array of TMonster;
    Npcs: array of TNpc;
    Player: TPlayer;
    Seed: LongWord;
    Done, Won: Boolean;
    function  NextRand(n: Integer): Integer;     { [0,n) — swap for random lib later }
    procedure LoadWorld(const path: AnsiString);
    function  FindRoom(const id: AnsiString): TRoom;
    function  FindMonster(const id: AnsiString): TMonster;
    function  FindNpc(const id: AnsiString): TNpc;
    function  CatalogItem(const id: AnsiString): TItem;
    function  Has(const id: AnsiString): Boolean;
    procedure Give(const id: AnsiString);
    function  CurRoom: TRoom;
    procedure Describe;
    procedure Move(d: TDirection);
    procedure Solve;
    procedure Talk(const who: AnsiString);
    procedure RevealHidden;
    procedure SaveTo(const path: AnsiString);
    procedure LoadFrom(const path: AnsiString);
    procedure Run;
  end;

implementation

const
  ESC = #27;
  RED = 31; GRN = 32; YEL = 33; BLU = 34; MAG = 35; CYN = 36;
  GREY = 90; WHT = 97;

  E_WRONG = 15; E_JMP = 20; E_XOR = 10; E_FLASK = 40; E_NOP = 5;

function NumStr(n: Integer): AnsiString;
var neg: Boolean;
begin
  if n = 0 then begin Result := '0'; Exit; end;
  neg := n < 0; if neg then n := -n;
  Result := '';
  while n > 0 do begin Result := Chr(Ord('0') + (n mod 10)) + Result; n := n div 10; end;
  if neg then Result := '-' + Result;
end;

function Col(const s: AnsiString; code: Integer): AnsiString;
begin Result := ESC + '[' + NumStr(code) + 'm' + s + ESC + '[0m'; end;

function Col256(const s: AnsiString; n: Integer): AnsiString;
begin Result := ESC + '[38;5;' + NumStr(n) + 'm' + s + ESC + '[0m'; end;

function Bold(const s: AnsiString): AnsiString;
begin Result := ESC + '[1m' + s + ESC + '[0m'; end;

function LowerStr(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  Result := s;
  for i := 1 to Length(Result) do
  begin c := Result[i]; if (c >= 'A') and (c <= 'Z') then Result[i] := Chr(Ord(c) + 32); end;
end;

function Trim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1; b := Length(s);
  while (a <= b) and (s[a] <= ' ') do Inc(a);
  while (b >= a) and (s[b] <= ' ') do Dec(b);
  Result := Copy(s, a, b - a + 1);
end;

function SplitOn(const s: AnsiString; sep: Char; var head, tail: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to Length(s) do
    if s[i] = sep then
    begin
      head := Trim(Copy(s, 1, i - 1)); tail := Trim(Copy(s, i + 1, Length(s)));
      Result := True; Exit;
    end;
  head := Trim(s); tail := '';
end;

procedure FirstWord(const s: AnsiString; var w, rest: AnsiString);
var i: Integer;
begin
  i := 1; while (i <= Length(s)) and (s[i] > ' ') do Inc(i);
  w := Copy(s, 1, i - 1); rest := Trim(Copy(s, i, Length(s)));
end;

function DirName(d: TDirection): AnsiString;
begin
  case d of
    dirNorth: Result := 'north'; dirSouth: Result := 'south';
    dirEast:  Result := 'east';  dirWest:  Result := 'west';
    dirUp:    Result := 'up';    dirDown:  Result := 'down';
  end;
end;

function NameToDir(const s: AnsiString; var d: TDirection): Boolean;
var t: AnsiString;
begin
  Result := True; t := LowerStr(s);
  if      (t = 'north') or (t = 'n') then d := dirNorth
  else if (t = 'south') or (t = 's') then d := dirSouth
  else if (t = 'east')  or (t = 'e') then d := dirEast
  else if (t = 'west')  or (t = 'w') then d := dirWest
  else if (t = 'up')    or (t = 'u') then d := dirUp
  else if (t = 'down')  or (t = 'd') then d := dirDown
  else Result := False;
end;

function SpellName(sp: TSpell): AnsiString;
begin
  case sp of
    spNop: Result := 'NOP'; spJmp: Result := 'JMP'; spXor: Result := 'XOR';
    spAnd: Result := 'AND'; spOr:  Result := 'OR';  spHalt: Result := 'HALT';
  end;
end;

function SpellByName(const s: AnsiString; var sp: TSpell): Boolean;
var t: AnsiString;
begin
  Result := True; t := LowerStr(s);
  if      t = 'nop'  then sp := spNop
  else if t = 'jmp'  then sp := spJmp
  else if t = 'xor'  then sp := spXor
  else if t = 'and'  then sp := spAnd
  else if t = 'or'   then sp := spOr
  else if t = 'halt' then sp := spHalt
  else Result := False;
end;

{ ----- art --------------------------------------------------------- }
procedure Splash;
var i: Integer;
begin
  WriteLn;
  WriteLn(Col256('  ##### ##### #####  ####  ####  #####', 51));
  WriteLn(Col256('  #     #     #     #    # #   # #    ', 45));
  WriteLn(Col256('  ##### ##### #     ##### #   # #####', 39));
  WriteLn(Col256('  #         # #     #   # #   # #    ', 33));
  WriteLn(Col256('  ##### ##### ##### #    ####  #####', 27));
  Write('  ');
  for i := 16 to 39 do Write(Col256('#', 232 + (i mod 24)));
  WriteLn;
  WriteLn(Bold(Col('        F R O M   T H E   M A C H I N E', CYN)));
  WriteLn;
end;

procedure DrawArt(const name: AnsiString);
begin
  if name = 'cpu' then
  begin
    WriteLn(Col256('        .----------------.', 81));
    WriteLn(Col256('        | []  []  []  [] |', 81));
    WriteLn(Col256('     ===|     C P U      |===', 75));
    WriteLn(Col256('        | []  []  []  [] |', 81));
    WriteLn(Col256('        ''----------------''', 81));
  end
  else if name = 'alu' then
  begin
    WriteLn(Col256('      >>> [ + - x / ] <<<', 196));
    WriteLn(Col256('       \   carry?!?   /', 202));
    WriteLn(Col256('        \__ A L U __/', 208));
  end
  else if name = 'ram' then
  begin
    WriteLn(Col256('  |#|#|#|#| |#|#|#|#| |#|#|', 135));
    WriteLn(Col256('  |#|#|#|#| |#|#|#|#| |#|#|  refresh~', 99));
  end
  else if name = 'cache' then
  begin
    WriteLn(Col256('  [tag|tag|tag|tag]  L?', 123));
    WriteLn(Col256('  [way][way][way]  *hit?*', 117));
  end
  else if name = 'reg' then
  begin
    WriteLn(Col256('  r0 r1 r2 r3 r4 r5 r6 r7', 159));
    WriteLn(Col256('  [][] [][] [][] [][]', 153));
  end
  else if name = 'pipe' then
  begin
    WriteLn(Col256('  IF | ID | EX | MEM | WB', 45));
    WriteLn(Col256('  >>>>>>>>>> stall? >>>>>>', 39));
  end
  else if name = 'ivt' then
  begin
    WriteLn(Col256('  IRQ0 IRQ1 .. IRQ255', 213));
    WriteLn(Col256('   |    |        |  *vector*', 207));
  end
  else if name = 'disk' then
  begin
    WriteLn(Col256('      _____________', 220));
    WriteLn(Col256('     /   o   o   o /|  ~SATA~', 220));
    WriteLn(Col256('    /_____________/ |', 214));
    WriteLn(Col256('    |__spinning____|/', 214));
  end
  else if name = 'psu' then
  begin
    WriteLn(Col256('     [~~~] 230V [~~~]', 46));
    WriteLn(Col256('      ||  P S U  ||  *hum*', 40));
  end
  else if name = 'bus' then
  begin
    WriteLn(Col256('  ==>==>==>==>==>==>==>', 33));
    WriteLn(Col256('  <==<==<==<==<==<==<==', 39));
  end
  else if name = 'ghost' then
  begin
    WriteLn(Col256('   . : ~ uninitialised ~ : .', 240));
    WriteLn(Col256('   garbage   0xDEADBEEF   ?', 244));
  end
  else if name = 'kernel' then
  begin
    WriteLn(Col256('   !!!  K E R N E L  !!!', 196));
    WriteLn(Col256('   [ PANIC -- not syncing ]', 160));
    WriteLn(Col256('    \________________/', 124));
  end
  else if name = 'port' then
  begin
    WriteLn(Col256('      ___________', 231));
    WriteLn(Col256('     |  [=====]  |  >>> OUTSIDE >>>', 231));
    WriteLn(Col256('     |__I/O_PORT_|', 252));
  end;
end;

{ ----- TPlayer ----------------------------------------------------- }
function TPlayer.GetAlive: Boolean;
begin Result := Energy > 0; end;

{ ----- TMonster / TBoss -------------------------------------------- }
function TMonster.Fight(const guess: AnsiString): Boolean;
begin
  if (CurIdx < 0) or (CurIdx >= Length(Riddles)) then begin Result := True; Exit; end;
  Result := LowerStr(Trim(guess)) = LowerStr(Trim(Riddles[CurIdx].A));
end;

function TMonster.Taunt: AnsiString;
begin Result := Name + ' bars the way.'; end;

function TBoss.Taunt: AnsiString;
begin Result := '*** ' + Name + ' rises, dripping stack frames. This is the end. ***'; end;

{ ----- TGame: PRNG ------------------------------------------------- }
function TGame.NextRand(n: Integer): Integer;
begin
  { xorshift32 — deterministic stopgap; the random-library ticket replaces this }
  Seed := Seed xor (Seed shl 13);
  Seed := Seed xor (Seed shr 17);
  Seed := Seed xor (Seed shl 5);
  if n <= 0 then Result := 0
  else Result := Integer(Seed mod LongWord(n));
end;

{ ----- finders ----------------------------------------------------- }
function TGame.FindRoom(const id: AnsiString): TRoom;
var r: TRoom;
begin Result := nil; for r in Rooms do if r.Id = id then begin Result := r; Exit; end; end;

function TGame.FindMonster(const id: AnsiString): TMonster;
var m: TMonster;
begin Result := nil; for m in Monsters do if m.Id = id then begin Result := m; Exit; end; end;

function TGame.FindNpc(const id: AnsiString): TNpc;
var n: TNpc;
begin Result := nil; for n in Npcs do if n.Id = id then begin Result := n; Exit; end; end;

function TGame.CatalogItem(const id: AnsiString): TItem;
var it: TItem;
begin
  Result.Id := ''; Result.Name := id; Result.Desc := '';
  for it in Catalog do if it.Id = id then begin Result := it; Exit; end;
end;

function TGame.Has(const id: AnsiString): Boolean;
var it: TItem;
begin Result := False; for it in Player.Inventory do if it.Id = id then begin Result := True; Exit; end; end;

procedure TGame.Give(const id: AnsiString);
var n: Integer;
begin
  if Has(id) then Exit;
  n := Length(Player.Inventory); SetLength(Player.Inventory, n + 1);
  Player.Inventory[n] := CatalogItem(id);
end;

function TGame.CurRoom: TRoom;
begin Result := FindRoom(Player.RoomId); end;

{ ----- describe ---------------------------------------------------- }
procedure TGame.Describe;
var r: TRoom; m: TMonster; np: TNpc; ex: TExit; iid: AnsiString; it: TItem;
begin
  r := CurRoom;
  WriteLn; DrawArt(r.Art); WriteLn;
  WriteLn(Bold(Col('== ' + r.Name + ' ==', WHT)));
  WriteLn(r.Desc);
  r.Visited := True;

  if Length(r.Items) > 0 then
  begin
    WriteLn;
    for iid in r.Items do
    begin it := CatalogItem(iid); WriteLn(Col('  * here lies ' + it.Name + '.', GRN)); end;
  end;

  if r.NpcId <> '' then
  begin
    np := FindNpc(r.NpcId);
    if np <> nil then
      WriteLn(Col('  @ ' + np.Name + ' is here. (type ' + Bold('talk') + ')', CYN));
  end;

  if r.MonsterId <> '' then
  begin
    m := FindMonster(r.MonsterId);
    if (m <> nil) and (not m.Defeated) then
    begin
      WriteLn;
      WriteLn(Col('  ! ' + m.Taunt, RED));
      WriteLn(Col('    ' + m.Desc, GREY));
      WriteLn(Col('    (type ' + Bold('solve') + ' to face it)', GREY));
    end;
  end;

  WriteLn;
  Write(Col('  exits: ', CYN));
  for ex in r.Exits do
    if not ex.Hidden then Write(Col(DirName(ex.Dir) + ' ', CYN));
  WriteLn;
end;

{ ----- movement ---------------------------------------------------- }
procedure TGame.Move(d: TDirection);
var r, dest: TRoom; ex: TExit; found: Boolean; m: TMonster; tgt, key: AnsiString;
begin
  r := CurRoom;
  if r.MonsterId <> '' then
  begin
    m := FindMonster(r.MonsterId);
    if (m <> nil) and (not m.Defeated) then
    begin WriteLn(Col('  ' + m.Name + ' will not let you pass. Face it first.', RED)); Exit; end;
  end;

  found := False; tgt := ''; key := '';
  for ex in r.Exits do
    if (ex.Dir = d) and (not ex.Hidden) then
    begin found := True; tgt := ex.Target; key := ex.KeyItem; end;

  if not found then begin WriteLn(Col('  You cannot go ' + DirName(d) + '.', YEL)); Exit; end;

  if (key <> '') and (not Has(key)) then
  begin
    WriteLn(Col('  The way ' + DirName(d) + ' is sealed. You lack ' +
                CatalogItem(key).Name + '.', YEL));
    Exit;
  end;

  dest := FindRoom(tgt);
  if dest = nil then begin WriteLn(Col('  (the world frays there)', GREY)); Exit; end;
  Player.RoomId := dest.Id;

  if (dest.WinItem <> '') and Has(dest.WinItem) then
  begin
    Describe; WriteLn;
    WriteLn(Bold(Col('You step through the jack into raw daylight.', GRN)));
    WriteLn(Bold(Col('You are OUTSIDE. You are FREE.', GRN)));
    Done := True; Won := True; Exit;
  end;
  Describe;
end;

{ ----- combat (riddle bank + random selection) --------------------- }
procedure TGame.Solve;
var r: TRoom; m: TMonster; guess: AnsiString;
begin
  r := CurRoom;
  if r.MonsterId = '' then begin WriteLn(Col('  Nothing here to face.', GREY)); Exit; end;
  m := FindMonster(r.MonsterId);
  if (m = nil) or m.Defeated then begin WriteLn(Col('  The way is already clear.', GREY)); Exit; end;
  if Length(m.Riddles) = 0 then begin m.Defeated := True; Exit; end;

  if (m.Needs <> '') and (not Has(m.Needs)) then
  begin
    WriteLn(Col('  You cannot face ' + m.Name + ' without ' +
                CatalogItem(m.Needs).Name + '.', YEL));
    Exit;
  end;

  if m.RoundsNeeded <= 0 then m.RoundsNeeded := Length(m.Riddles);

  if not m.Asking then
  begin
    m.CurIdx := NextRand(Length(m.Riddles));   { random riddle from the bank }
    m.Asking := True;
  end;

  WriteLn;
  WriteLn(Col('  ' + m.Riddles[m.CurIdx].Q, MAG));
  Write(Col('  > ', MAG)); ReadLn(guess);
  m.Asking := False;

  if m.Fight(guess) then
  begin
    m.Progress := m.Progress + 1;
    if m.Progress >= m.RoundsNeeded then
    begin
      WriteLn(Col('  ' + m.Name + ' dissolves into clean logic.', GRN));
      m.Defeated := True;
      if m.RewardKind = 'item' then
      begin Give(m.RewardArg); WriteLn(Col('  You gain ' + CatalogItem(m.RewardArg).Name + '.', GRN)); end
      else if m.RewardKind = 'spell' then
      begin
        if m.RewardArg = 'xor' then Player.Spells := Player.Spells + [spXor]
        else if m.RewardArg = 'and' then Player.Spells := Player.Spells + [spAnd]
        else if m.RewardArg = 'or'  then Player.Spells := Player.Spells + [spOr]
        else if m.RewardArg = 'jmp' then Player.Spells := Player.Spells + [spJmp];
        WriteLn(Col('  You learn the spell ' + LowerStr(m.RewardArg) + '!', GRN));
      end
      else WriteLn(Col('  The path opens.', GRN));
    end
    else
      WriteLn(Col('  Correct. It reels — but is not done. (' +
                  NumStr(m.RoundsNeeded - m.Progress) + ' to go)', GRN));
  end
  else
  begin
    Player.Energy := Player.Energy - E_WRONG;
    WriteLn(Col('  Wrong. The machine bites. (-' + NumStr(E_WRONG) + ' energy)', RED));
    m.Progress := 0;   { botch resets the gauntlet }
  end;
end;

{ ----- NPCs -------------------------------------------------------- }
procedure TGame.Talk(const who: AnsiString);
var r: TRoom; np: TNpc; ln, want: AnsiString;
begin
  r := CurRoom;
  want := LowerStr(Trim(who));
  if want <> '' then np := FindNpc(want) else np := FindNpc(r.NpcId);
  if (np = nil) and (r.NpcId <> '') then np := FindNpc(r.NpcId);
  if np = nil then begin WriteLn(Col('  No one here to talk to.', GREY)); Exit; end;

  WriteLn(Bold(Col('  ' + np.Name + ':', CYN)));
  for ln in np.Lines do                       { for..in over dialogue lines }
    WriteLn(Col('   "' + ln + '"', CYN));

  if (np.Gift <> '') and (not np.Given) and
     ((np.Needs = '') or Has(np.Needs)) then
  begin
    Give(np.Gift); np.Given := True;
    if np.GiftText <> '' then WriteLn(Col('  ' + np.GiftText, GRN));
    WriteLn(Col('  (you receive ' + CatalogItem(np.Gift).Name + ')', GRN));
  end;
end;

{ ----- XOR reveals hidden exits ------------------------------------ }
procedure TGame.RevealHidden;
var r: TRoom; i: Integer; any: Boolean;
begin
  r := CurRoom; any := False;
  for i := 0 to High(r.Exits) do
    if r.Exits[i].Hidden then begin r.Exits[i].Hidden := False; any := True; end;
  if any then WriteLn(Col('  Hidden lanes shimmer into existence!', MAG))
  else WriteLn(Col('  XOR ripples outward. Nothing new appears here.', GREY));
end;

{ ----- save / load ------------------------------------------------- }
procedure TGame.SaveTo(const path: AnsiString);
var f: Text; it: TItem; sp: TSpell; m: TMonster;
begin
  Assign(f, path); Rewrite(f);
  WriteLn(f, 'room=' + Player.RoomId);
  WriteLn(f, 'energy=' + NumStr(Player.Energy));
  for it in Player.Inventory do WriteLn(f, 'item=' + it.Id);
  for sp in Player.Spells do WriteLn(f, 'spell=' + LowerStr(SpellName(sp)));
  for m in Monsters do if m.Defeated then WriteLn(f, 'defeated=' + m.Id);
  Close(f);
  WriteLn(Col('  Saved.', GRN));
end;

procedure TGame.LoadFrom(const path: AnsiString);
var f: Text; line, key, val: AnsiString; sp: TSpell; m: TMonster;
begin
  Assign(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then begin WriteLn(Col('  No save found.', YEL)); Exit; end;

  SetLength(Player.Inventory, 0);
  Player.Spells := [spNop];
  for m in Monsters do begin m.Defeated := False; m.Progress := 0; m.Asking := False; end;

  while not Eof(f) do
  begin
    ReadLn(f, line); line := Trim(line);
    if not SplitOn(line, '=', key, val) then Continue;
    if      key = 'room'     then Player.RoomId := val
    else if key = 'energy'   then Player.Energy := StrToIntDef(val, 100)
    else if key = 'item'     then Give(val)
    else if key = 'spell'    then begin if SpellByName(val, sp) then Player.Spells := Player.Spells + [sp]; end
    else if key = 'defeated' then begin m := FindMonster(val); if m <> nil then m.Defeated := True; end;
  end;
  Close(f);
  WriteLn(Col('  Loaded.', GRN)); Describe;
end;

{ ----- world loader ------------------------------------------------ }
procedure TGame.LoadWorld(const path: AnsiString);
var
  f: Text; line, key, val, h, t: AnsiString;
  kind, ridx, midx, nidx, n: Integer; d: TDirection; pendingQ: AnsiString;

  procedure AddExit(roomI: Integer; hidden: Boolean; const spec: AnsiString);
  var dd: TDirection; a, b, c: AnsiString; k: Integer;
  begin
    if not SplitOn(spec, ':', a, b) then Exit;
    if not NameToDir(a, dd) then Exit;
    k := Length(Rooms[roomI].Exits); SetLength(Rooms[roomI].Exits, k + 1);
    Rooms[roomI].Exits[k].Dir := dd;
    Rooms[roomI].Exits[k].Hidden := hidden;
    if SplitOn(b, ':', a, c) then
    begin Rooms[roomI].Exits[k].Target := a; Rooms[roomI].Exits[k].KeyItem := c; end
    else
    begin Rooms[roomI].Exits[k].Target := b; Rooms[roomI].Exits[k].KeyItem := ''; end;
  end;

begin
  kind := 0; ridx := -1; midx := -1; nidx := -1; pendingQ := '';
  Assign(f, path); Reset(f);
  while not Eof(f) do
  begin
    ReadLn(f, line); line := Trim(line);
    if (line = '') or (line[1] = '#') then Continue;

    if line[1] = '[' then
    begin
      pendingQ := '';
      if line = '[room]' then
      begin kind := 1; n := Length(Rooms); SetLength(Rooms, n + 1); Rooms[n] := TRoom.Create; ridx := n; end
      else if line = '[item]' then
      begin kind := 2; n := Length(Catalog); SetLength(Catalog, n + 1); end
      else if (line = '[monster]') or (line = '[boss]') then
      begin
        kind := 3; n := Length(Monsters); SetLength(Monsters, n + 1);
        if line = '[boss]' then Monsters[n] := TBoss.Create else Monsters[n] := TMonster.Create;
        midx := n;
      end
      else if line = '[npc]' then
      begin kind := 4; n := Length(Npcs); SetLength(Npcs, n + 1); Npcs[n] := TNpc.Create; nidx := n; end;
      Continue;
    end;

    if not SplitOn(line, '=', key, val) then Continue;
    key := LowerStr(key);

    case kind of
      1:
        begin
          if      key = 'id'      then Rooms[ridx].Id := val
          else if key = 'name'    then Rooms[ridx].Name := val
          else if key = 'art'     then Rooms[ridx].Art := val
          else if key = 'desc'    then Rooms[ridx].Desc := val
          else if key = 'monster' then Rooms[ridx].MonsterId := val
          else if key = 'npc'     then Rooms[ridx].NpcId := val
          else if key = 'win'     then Rooms[ridx].WinItem := val
          else if key = 'item'    then
          begin n := Length(Rooms[ridx].Items); SetLength(Rooms[ridx].Items, n + 1); Rooms[ridx].Items[n] := val; end
          else if key = 'exit'  then AddExit(ridx, False, val)
          else if key = 'hexit' then AddExit(ridx, True,  val);
        end;
      2:
        begin
          n := High(Catalog);
          if      key = 'id'   then Catalog[n].Id := val
          else if key = 'name' then Catalog[n].Name := val
          else if key = 'desc' then Catalog[n].Desc := val;
        end;
      3:
        begin
          if      key = 'id'     then Monsters[midx].Id := val
          else if key = 'name'   then Monsters[midx].Name := val
          else if key = 'art'    then Monsters[midx].Art := val
          else if key = 'desc'   then Monsters[midx].Desc := val
          else if key = 'needs'  then Monsters[midx].Needs := val
          else if key = 'rounds' then Monsters[midx].RoundsNeeded := StrToIntDef(val, 0)
          else if key = 'puzzle' then pendingQ := val
          else if key = 'answer' then
          begin
            n := Length(Monsters[midx].Riddles); SetLength(Monsters[midx].Riddles, n + 1);
            Monsters[midx].Riddles[n].Q := pendingQ; Monsters[midx].Riddles[n].A := val; pendingQ := '';
          end
          else if key = 'reward' then
          begin SplitOn(val, ':', h, t); Monsters[midx].RewardKind := h; Monsters[midx].RewardArg := t; end;
        end;
      4:
        begin
          if      key = 'id'       then Npcs[nidx].Id := val
          else if key = 'name'     then Npcs[nidx].Name := val
          else if key = 'art'      then Npcs[nidx].Art := val
          else if key = 'desc'     then Npcs[nidx].Desc := val
          else if key = 'gift'     then Npcs[nidx].Gift := val
          else if key = 'gifttext' then Npcs[nidx].GiftText := val
          else if key = 'needs'    then Npcs[nidx].Needs := val
          else if key = 'line'     then
          begin n := Length(Npcs[nidx].Lines); SetLength(Npcs[nidx].Lines, n + 1); Npcs[nidx].Lines[n] := val; end;
        end;
    end;
  end;
  Close(f);
end;

{ ----- command handlers -------------------------------------------- }
type
  TCmd  = procedure(g: TGame; const arg: AnsiString);
  TVerb = record Word: AnsiString; Run: TCmd; end;

procedure CmdLook(g: TGame; const arg: AnsiString); begin g.Describe; end;

procedure CmdInv(g: TGame; const arg: AnsiString);
var it: TItem; sp: TSpell; any: Boolean;
begin
  WriteLn(Bold('You carry:'));
  if Length(g.Player.Inventory) = 0 then WriteLn(Col('  (nothing)', GREY))
  else for it in g.Player.Inventory do WriteLn(Col('  - ' + it.Name, GRN));
  any := False; for sp in g.Player.Spells do any := True;
  if any then
  begin
    Write(Bold('Spells: '));
    for sp in g.Player.Spells do Write(Col(SpellName(sp) + ' ', MAG));
    WriteLn;
  end;
  WriteLn(Col('Energy: ' + NumStr(g.Player.Energy), YEL));
end;

procedure CmdTake(g: TGame; const arg: AnsiString);
var r: TRoom; i, n: Integer; want, iid: AnsiString; took: Boolean;
begin
  r := g.CurRoom; want := LowerStr(Trim(arg)); took := False;
  for i := 0 to High(r.Items) do
  begin
    iid := r.Items[i];
    if (want = '') or (want = iid) or (Pos(want, LowerStr(g.CatalogItem(iid).Name)) > 0) then
    begin
      g.Give(iid); WriteLn(Col('  Taken: ' + g.CatalogItem(iid).Name, GRN));
      for n := i to High(r.Items) - 1 do r.Items[n] := r.Items[n + 1];
      SetLength(r.Items, Length(r.Items) - 1); took := True; Break;
    end;
  end;
  if not took then WriteLn(Col('  Nothing like that here.', YEL));
end;

procedure CmdExamine(g: TGame; const arg: AnsiString);
var it: TItem; want: AnsiString;
begin
  want := LowerStr(Trim(arg));
  for it in g.Player.Inventory do
    if (want = it.Id) or (Pos(want, LowerStr(it.Name)) > 0) then begin WriteLn(it.Desc); Exit; end;
  WriteLn(Col('  You are not carrying that.', YEL));
end;

procedure CmdSolve(g: TGame; const arg: AnsiString); begin g.Solve; end;
procedure CmdTalk(g: TGame; const arg: AnsiString); begin g.Talk(arg); end;

procedure CmdDrink(g: TGame; const arg: AnsiString);
var i: Integer;
begin
  for i := 0 to High(g.Player.Inventory) do
    if g.Player.Inventory[i].Id = 'flask' then
    begin
      g.Player.Energy := g.Player.Energy + E_FLASK;
      WriteLn(Col('  You drink the 3V3. (+' + NumStr(E_FLASK) + ' energy)', GRN));
      for i := i to High(g.Player.Inventory) - 1 do g.Player.Inventory[i] := g.Player.Inventory[i + 1];
      SetLength(g.Player.Inventory, Length(g.Player.Inventory) - 1); Exit;
    end;
  WriteLn(Col('  You have no flask.', YEL));
end;

procedure CmdCast(g: TGame; const arg: AnsiString);
var sp: TSpell;
begin
  if not SpellByName(arg, sp) then begin WriteLn(Col('  Unknown spell.', YEL)); Exit; end;
  if not (sp in g.Player.Spells) then begin WriteLn(Col('  You have not learned that spell.', YEL)); Exit; end;
  case sp of
    spNop:
      begin g.Player.Energy := g.Player.Energy + E_NOP;
        WriteLn(Col('  You execute NOP. A moment of calm. (+' + NumStr(E_NOP) + ')', GREY)); end;
    spJmp:
      begin g.Player.Energy := g.Player.Energy - E_JMP;
        WriteLn(Col('  JMP! You snap back to the ALU Chamber. (-' + NumStr(E_JMP) + ')', MAG));
        g.Player.RoomId := 'cpu_die'; g.Describe; end;
    spXor:
      begin g.Player.Energy := g.Player.Energy - E_XOR;
        WriteLn(Col('  XOR crackles. (-' + NumStr(E_XOR) + ')', MAG));
        g.RevealHidden; end;
  else
    WriteLn(Col('  The spell fizzles, purely decorative.', GREY));
  end;
end;

procedure CmdSave(g: TGame; const arg: AnsiString); begin g.SaveTo('adventure.sav'); end;
procedure CmdLoad(g: TGame; const arg: AnsiString); begin g.LoadFrom('adventure.sav'); end;

procedure CmdGo(g: TGame; const arg: AnsiString);
var d: TDirection;
begin if NameToDir(arg, d) then g.Move(d) else WriteLn(Col('  Go where?', YEL)); end;

procedure CmdHelp(g: TGame; const arg: AnsiString);
begin
  WriteLn(Bold('Commands:'));
  WriteLn('  look | n/s/e/w/u/d | go <dir>');
  WriteLn('  take [thing] | inventory(i) | examine(x) <thing>');
  WriteLn('  talk [who] | solve | cast <spell> | drink');
  WriteLn('  save | load | help | quit');
end;

procedure CmdQuit(g: TGame; const arg: AnsiString);
begin WriteLn(Col('  The machine keeps you. (quit)', GREY)); g.Done := True; end;

{ ----- main loop --------------------------------------------------- }
procedure TGame.Run;
var
  verbs: array of TVerb;
  v: TVerb; line, w, rest: AnsiString; d: TDirection; handled: Boolean;

  { nested procedure capturing the local `verbs` — deliberate frame-capture test }
  procedure AddVerb(const word: AnsiString; c: TCmd);
  var n: Integer;
  begin
    n := Length(verbs); SetLength(verbs, n + 1);
    verbs[n].Word := word; verbs[n].Run := c;
  end;

begin
  AddVerb('look', @CmdLook);       AddVerb('l', @CmdLook);
  AddVerb('inventory', @CmdInv);   AddVerb('i', @CmdInv);
  AddVerb('take', @CmdTake);       AddVerb('get', @CmdTake);
  AddVerb('examine', @CmdExamine); AddVerb('x', @CmdExamine);
  AddVerb('talk', @CmdTalk);       AddVerb('t', @CmdTalk);
  AddVerb('solve', @CmdSolve);     AddVerb('fight', @CmdSolve);
  AddVerb('cast', @CmdCast);       AddVerb('drink', @CmdDrink);
  AddVerb('go', @CmdGo);           AddVerb('help', @CmdHelp);
  AddVerb('save', @CmdSave);       AddVerb('load', @CmdLoad);
  AddVerb('quit', @CmdQuit);

  Splash;
  WriteLn('You are trapped inside the computer. Find the I/O port and escape.');
  WriteLn('Type ' + Bold('help') + ' for commands.');
  Describe;

  while (not Done) and Player.Alive do
  begin
    WriteLn;
    Write(Col('machine[', WHT)); Write(Col(NumStr(Player.Energy), YEL)); Write(Col(']> ', WHT));
    ReadLn(line); line := Trim(line);
    if line = '' then Continue;
    FirstWord(line, w, rest); w := LowerStr(w);

    if NameToDir(w, d) then begin Move(d); Continue; end;

    handled := False;
    for v in verbs do
      if v.Word = w then begin v.Run(Self, rest); handled := True; Break; end;
    if not handled then WriteLn(Col('  The machine does not understand "' + w + '".', YEL));
  end;

  WriteLn;
  if Won then WriteLn(Bold(Col('*** YOU ESCAPED ***', GRN)))
  else if not Player.Alive then WriteLn(Bold(Col('*** YOU BROWNED OUT. The machine reclaims you. ***', RED)))
  else WriteLn(Bold(Col('*** STILL TRAPPED ***', RED)));
end;

end.
