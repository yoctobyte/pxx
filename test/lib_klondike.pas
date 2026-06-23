program lib_klondike;
{ Klondike engine test: exhaustive pure move predicates, the seeded deal layout,
  the 52-card invariant, draw/recycle, and move+undo round-trips verified by a
  position-sensitive board checksum (any undo that does not exactly restore the
  board is caught). }

uses klondike;

var
  fails, i, col: Integer;
  tag: string;

procedure CKb(const tag: string; got: Boolean);
begin
  if got then writeln(tag, '=ok') else begin writeln(tag, '=bad'); fails := fails + 1; end;
end;

procedure CKi(const tag: string; got, want: Integer);
begin
  if got = want then writeln(tag, '=ok')
  else begin writeln(tag, '=bad ', got, '/', want); fails := fails + 1; end;
end;

function Checksum: Integer;
var pp, ii, s: Integer;
begin
  s := 0;
  for pp := 0 to N_PILES - 1 do
  begin
    s := s + (pp + 1) * 1000003 + PileCount(pp) * 97;
    for ii := 0 to PileCount(pp) - 1 do
    begin
      s := s + (pp * 53 + ii + 1) *
        (CardSuit(pp, ii) * 100 + CardRank(pp, ii) * 4 + Ord(CardFaceUp(pp, ii)) + 1);
    end;
  end;
  Checksum := s;
end;

function TotalCards: Integer;
var pp, t: Integer;
begin
  t := 0;
  for pp := 0 to N_PILES - 1 do t := t + PileCount(pp);
  TotalCards := t;
end;

var snap, moved, sCol, dCol: Integer; foundMove: Boolean;

begin
  fails := 0;

  { ---- pure predicates ---- }
  CKb('red-d', IsRed(1));       { diamonds }
  CKb('red-h', IsRed(2));       { hearts }
  CKb('blk-c', not IsRed(0));   { clubs }
  CKb('blk-s', not IsRed(3));   { spades }
  { tableau: red 6 on black 7 ok; same colour / wrong rank no; King on empty yes }
  CKb('tab-ok',     TableauAccepts(1, 6, 0, 7, False));
  CKb('tab-color',  not TableauAccepts(1, 6, 2, 7, False));   { red on red }
  CKb('tab-rank',   not TableauAccepts(1, 5, 0, 7, False));
  CKb('tab-king',   TableauAccepts(3, 13, 0, 0, True));
  CKb('tab-noking', not TableauAccepts(3, 12, 0, 0, True));
  { foundation: ace on empty; 2 same suit on ace; wrong suit/rank no }
  CKb('fnd-ace',    FoundationAccepts(2, 1, 0, 0, True));
  CKb('fnd-up',     FoundationAccepts(2, 2, 2, 1, False));
  CKb('fnd-suit',   not FoundationAccepts(3, 2, 2, 1, False));
  CKb('fnd-rank',   not FoundationAccepts(2, 3, 2, 1, False));

  { ---- deal layout ---- }
  NewGame(12345);
  for col := 0 to N_TAB - 1 do
  begin
    tag := 'tab-len-' + Chr(Ord('0') + col);   { var first: avoid concat-arg BSS bloat }
    CKi(tag, PileCount(P_TAB + col), col + 1);
  end;
  CKb('tab-top-faceup', CardFaceUp(P_TAB + 3, 3));      { col 3 top (index 3) is up }
  CKb('tab-under-down', not CardFaceUp(P_TAB + 3, 0));  { underneath is down }
  CKi('stock', PileCount(P_STOCK), 24);
  CKi('waste0', PileCount(P_WASTE), 0);
  CKi('total52', TotalCards, 52);
  CKb('not-won', not IsWon);

  { ---- draw + recycle ---- }
  DrawStock;
  CKi('draw-stock', PileCount(P_STOCK), 23);
  CKi('draw-waste', PileCount(P_WASTE), 1);
  CKb('waste-faceup', CardFaceUp(P_WASTE, 0));
  for i := 1 to 23 do DrawStock;          { drain the rest }
  CKi('drained-stock', PileCount(P_STOCK), 0);
  CKi('drained-waste', PileCount(P_WASTE), 24);
  DrawStock;                              { recycle }
  CKi('recycled-stock', PileCount(P_STOCK), 24);
  CKi('recycled-waste', PileCount(P_WASTE), 0);

  { ---- draw + undo round-trips to the exact board ---- }
  NewGame(777);
  snap := Checksum;
  DrawStock; DrawStock; DrawStock;
  CKb('draw-changed', Checksum <> snap);
  Undo; Undo; Undo;
  CKi('undo-restore', Checksum, snap);

  { ---- a real card move + undo, found deterministically across seeds ---- }
  foundMove := False;
  moved := 1;
  while (moved <= 50) and (not foundMove) do
  begin
    NewGame(moved);
    sCol := 0;
    while (sCol < N_TAB) and (not foundMove) do
    begin
      dCol := 0;
      while (dCol < N_TAB) and (not foundMove) do
      begin
        if (sCol <> dCol) and (PileCount(P_TAB + dCol) > 0) then
        begin
          snap := Checksum;
          if TryMove(P_TAB + sCol, P_TAB + dCol, 1) then
          begin
            foundMove := True;
            CKb('move-changed', Checksum <> snap);
            CKi('move-total', TotalCards, 52);
            Undo;
            CKi('move-undo', Checksum, snap);
          end;
        end;
        dCol := dCol + 1;
      end;
      sCol := sCol + 1;
    end;
    moved := moved + 1;
  end;
  CKb('found-a-move', foundMove);

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
