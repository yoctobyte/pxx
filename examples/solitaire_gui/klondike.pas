unit klondike;
{ Klondike solitaire engine — pure game logic, no UI. The board is a single
  global game held as fixed 2D arrays (13 piles x up to 52 cards + a per-pile
  count), the project's preferred shape over dynamic-array-of-record fields.
  Shared by the GUI front-end (and a console one). Move legality lives in pure
  predicates (TableauAccepts / FoundationAccepts) so it is exhaustively testable
  apart from the board state. }

interface

uses random;

const
  P_STOCK = 0;
  P_WASTE = 1;
  P_FOUND = 2;          { foundations: P_FOUND .. P_FOUND+3 }
  P_TAB   = 6;          { tableau:     P_TAB   .. P_TAB+6   }
  N_PILES = 13;
  N_FOUND = 4;
  N_TAB   = 7;

{ ---- pure move predicates (no board state) ---- }
function IsRed(suit: Integer): Boolean;
function TableauAccepts(cSuit, cRank, topSuit, topRank: Integer; destEmpty: Boolean): Boolean;
function FoundationAccepts(cSuit, cRank, topSuit, topRank: Integer; destEmpty: Boolean): Boolean;

{ ---- game ---- }
procedure NewGame(seed: Integer);
procedure DrawStock;                              { stock->waste, recycling when empty }
function TryMove(src, dst, count: Integer): Boolean;  { move count top cards, validated }
function AutoFoundation(src: Integer): Boolean;   { send src's top card to a foundation }
function IsWon: Boolean;
procedure Undo;
function CanUndo: Boolean;

{ ---- accessors for a renderer (field-wise, no record returns) ---- }
function PileCount(p: Integer): Integer;
function CardSuit(p, i: Integer): Integer;
function CardRank(p, i: Integer): Integer;
function CardFaceUp(p, i: Integer): Boolean;

implementation

type
  TCard = record suit, rank: Integer; faceUp: Boolean; end;
  TMove = record kind, src, dst, count: Integer; flipped: Boolean; end;

const
  MK_MOVE = 0;
  MK_DRAW = 1;
  MK_RECYCLE = 2;

var
  pile: array[0..N_PILES - 1, 0..51] of TCard;
  pcount: array[0..N_PILES - 1] of Integer;
  undoStack: array[0..511] of TMove;
  ucount: Integer;

function IsRed(suit: Integer): Boolean;
begin
  IsRed := (suit = 1) or (suit = 2);   { 1=Diamonds, 2=Hearts }
end;

function TableauAccepts(cSuit, cRank, topSuit, topRank: Integer; destEmpty: Boolean): Boolean;
begin
  if destEmpty then
    TableauAccepts := (cRank = 13)                                  { only a King on an empty column }
  else
    TableauAccepts := (IsRed(cSuit) <> IsRed(topSuit)) and (cRank = topRank - 1);
end;

function FoundationAccepts(cSuit, cRank, topSuit, topRank: Integer; destEmpty: Boolean): Boolean;
begin
  if destEmpty then
    FoundationAccepts := (cRank = 1)                                { only an Ace on an empty foundation }
  else
    FoundationAccepts := (cSuit = topSuit) and (cRank = topRank + 1);
end;

function PileCount(p: Integer): Integer;
begin
  PileCount := pcount[p];
end;

function CardSuit(p, i: Integer): Integer;
begin
  CardSuit := pile[p][i].suit;
end;

function CardRank(p, i: Integer): Integer;
begin
  CardRank := pile[p][i].rank;
end;

function CardFaceUp(p, i: Integer): Boolean;
begin
  CardFaceUp := pile[p][i].faceUp;
end;

procedure PushCard(p, suit, rank: Integer; faceUp: Boolean);
begin
  pile[p][pcount[p]].suit := suit;
  pile[p][pcount[p]].rank := rank;
  pile[p][pcount[p]].faceUp := faceUp;
  pcount[p] := pcount[p] + 1;
end;

procedure NewGame(seed: Integer);
var
  deck: array[0..51] of TCard;
  i, j, col, dealt: Integer;
  tmp: TCard;
begin
  { fresh 52-card deck }
  for i := 0 to 51 do
  begin
    deck[i].suit := i div 13;
    deck[i].rank := (i mod 13) + 1;
    deck[i].faceUp := False;
  end;
  { Fisher-Yates shuffle, seeded }
  RandSeed(LongWord(seed));
  for i := 51 downto 1 do
  begin
    j := Random(i + 1);
    tmp := deck[i]; deck[i] := deck[j]; deck[j] := tmp;
  end;

  for i := 0 to N_PILES - 1 do pcount[i] := 0;
  ucount := 0;

  { deal tableau: column c gets c+1 cards, only the last face up }
  dealt := 0;
  for col := 0 to N_TAB - 1 do
    for i := 0 to col do
    begin
      PushCard(P_TAB + col, deck[dealt].suit, deck[dealt].rank, i = col);
      dealt := dealt + 1;
    end;
  { the rest to the stock, face down }
  while dealt < 52 do
  begin
    PushCard(P_STOCK, deck[dealt].suit, deck[dealt].rank, False);
    dealt := dealt + 1;
  end;
end;

procedure PushUndo(kind, src, dst, count: Integer; flipped: Boolean);
begin
  if ucount > 511 then Exit;
  undoStack[ucount].kind := kind;
  undoStack[ucount].src := src;
  undoStack[ucount].dst := dst;
  undoStack[ucount].count := count;
  undoStack[ucount].flipped := flipped;
  ucount := ucount + 1;
end;

procedure DrawStock;
var i, n: Integer; tmp: TCard;
begin
  if pcount[P_STOCK] > 0 then
  begin
    n := pcount[P_STOCK] - 1;
    pile[P_WASTE][pcount[P_WASTE]] := pile[P_STOCK][n];
    pile[P_WASTE][pcount[P_WASTE]].faceUp := True;
    pcount[P_WASTE] := pcount[P_WASTE] + 1;
    pcount[P_STOCK] := n;
    PushUndo(MK_DRAW, 0, 0, 1, False);
  end
  else if pcount[P_WASTE] > 0 then
  begin
    { recycle waste back to stock, reversed and face down }
    for i := pcount[P_WASTE] - 1 downto 0 do
    begin
      tmp := pile[P_WASTE][i];
      tmp.faceUp := False;
      pile[P_STOCK][pcount[P_STOCK]] := tmp;
      pcount[P_STOCK] := pcount[P_STOCK] + 1;
    end;
    pcount[P_WASTE] := 0;
    PushUndo(MK_RECYCLE, 0, 0, 0, False);
  end;
end;

{ Are the top `count` cards of a tableau pile a valid face-up descending
  alternating-colour run that may be moved together? }
function ValidRun(src, count: Integer): Boolean;
var i, base: Integer; ok: Boolean;
begin
  base := pcount[src] - count;
  ok := True;
  for i := base to pcount[src] - 1 do
    if not pile[src][i].faceUp then ok := False;
  i := base;
  while (i < pcount[src] - 1) and ok do
  begin
    if (IsRed(pile[src][i].suit) = IsRed(pile[src][i + 1].suit)) or
       (pile[src][i].rank <> pile[src][i + 1].rank + 1) then ok := False;
    i := i + 1;
  end;
  ValidRun := ok;
end;

function TryMove(src, dst, count: Integer): Boolean;
var base, i, bSuit, bRank: Integer; flipped, destEmpty, ok: Boolean;
begin
  TryMove := False;
  if (count < 1) or (pcount[src] < count) then Exit;
  base := pcount[src] - count;
  if not pile[src][base].faceUp then Exit;             { can't move a face-down card }
  bSuit := pile[src][base].suit;
  bRank := pile[src][base].rank;

  ok := False;
  if (dst >= P_FOUND) and (dst < P_FOUND + N_FOUND) then
  begin
    if count = 1 then
    begin
      destEmpty := pcount[dst] = 0;
      if destEmpty then ok := FoundationAccepts(bSuit, bRank, 0, 0, True)
      else ok := FoundationAccepts(bSuit, bRank, pile[dst][pcount[dst]-1].suit,
                                   pile[dst][pcount[dst]-1].rank, False);
    end;
  end
  else if (dst >= P_TAB) and (dst < P_TAB + N_TAB) then
  begin
    if ValidRun(src, count) then
    begin
      destEmpty := pcount[dst] = 0;
      if destEmpty then ok := TableauAccepts(bSuit, bRank, 0, 0, True)
      else ok := TableauAccepts(bSuit, bRank, pile[dst][pcount[dst]-1].suit,
                                pile[dst][pcount[dst]-1].rank, False);
    end;
  end;
  if not ok then Exit;

  { execute: copy the run to dst, shrink src }
  for i := 0 to count - 1 do
    pile[dst][pcount[dst] + i] := pile[src][base + i];
  pcount[dst] := pcount[dst] + count;
  pcount[src] := base;

  { flip the newly exposed tableau card }
  flipped := False;
  if (src >= P_TAB) and (src < P_TAB + N_TAB) and (pcount[src] > 0) and
     (not pile[src][pcount[src]-1].faceUp) then
  begin
    pile[src][pcount[src]-1].faceUp := True;
    flipped := True;
  end;
  PushUndo(MK_MOVE, src, dst, count, flipped);
  TryMove := True;
end;

function AutoFoundation(src: Integer): Boolean;
var f: Integer;
begin
  AutoFoundation := False;
  if pcount[src] = 0 then Exit;
  for f := 0 to N_FOUND - 1 do
    if TryMove(src, P_FOUND + f, 1) then
    begin
      AutoFoundation := True;
      Exit;
    end;
end;

function IsWon: Boolean;
var f: Integer;
begin
  IsWon := True;
  for f := 0 to N_FOUND - 1 do
    if pcount[P_FOUND + f] <> 13 then IsWon := False;
end;

function CanUndo: Boolean;
begin
  CanUndo := ucount > 0;
end;

procedure Undo;
var m: TMove; i, n: Integer; tmp: TCard;
begin
  if ucount = 0 then Exit;
  ucount := ucount - 1;
  m := undoStack[ucount];
  if m.kind = MK_MOVE then
  begin
    { unflip first (the card we exposed on src goes back face down) }
    if m.flipped and (pcount[m.src] > 0) then
      pile[m.src][pcount[m.src]-1].faceUp := False;
    { move the run back dst->src }
    for i := 0 to m.count - 1 do
      pile[m.src][pcount[m.src] + i] := pile[m.dst][pcount[m.dst] - m.count + i];
    pcount[m.src] := pcount[m.src] + m.count;
    pcount[m.dst] := pcount[m.dst] - m.count;
  end
  else if m.kind = MK_DRAW then
  begin
    n := pcount[P_WASTE] - 1;
    pile[P_STOCK][pcount[P_STOCK]] := pile[P_WASTE][n];
    pile[P_STOCK][pcount[P_STOCK]].faceUp := False;
    pcount[P_STOCK] := pcount[P_STOCK] + 1;
    pcount[P_WASTE] := n;
  end
  else if m.kind = MK_RECYCLE then
  begin
    for i := pcount[P_STOCK] - 1 downto 0 do
    begin
      tmp := pile[P_STOCK][i];
      tmp.faceUp := True;
      pile[P_WASTE][pcount[P_WASTE]] := tmp;
      pcount[P_WASTE] := pcount[P_WASTE] + 1;
    end;
    pcount[P_STOCK] := 0;
  end;
end;

end.
