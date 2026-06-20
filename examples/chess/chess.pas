program Chess;
{ Flagship demo — a small but real mailbox chess engine.

  NOT a strong engine: a *real application* whose job is to exercise as much of
  the language surface as practical in one coherent program, and to act as a
  deterministic cross-target oracle (perft leaf counts are published integers).

  Written platonically: it assumes an idiomatic RTL (IntToStr / StrToInt /
  Exception). Where that RTL is missing, the gap is the point — see
  feature-rtl-conversion-and-bitset-library. No workarounds, no tests here.

  Feature surface (per feature-demo-chess):
    enums · sets (castling rights / move flags) · records (move/undo/position) ·
    static arrays (board, piece-square tables) · dynamic arrays (PV) ·
    recursion (negamax + perft) · Int64/UInt64 (Zobrist hashing) ·
    generators + for-in (move generation) · procedural types (eval term table) ·
    classes/VMT (TEngine + overriding descendant) · exceptions (FEN parse) ·
    managed strings (FEN + UCI-ish REPL) · open-addressed hash table (TT).

  Square numbering: 0 = a1 .. 7 = h1, 8 = a2 .. 63 = h8.  rank = sq div 8,
  file = sq mod 8.  White pawns advance +8. }

{$mode objfpc}

uses coroutine, sysutils;

const
  INF      = 30000;
  MATE     = 29000;
  TT_SIZE  = 1 shl 16;     { open-addressed transposition table slots }

type
  TColor = (cWhite, cBlack);

  TPieceKind = (pkNone, pkPawn, pkKnight, pkBishop, pkRook, pkQueen, pkKing);

  TPiece = record
    kind:  TPieceKind;
    color: TColor;
  end;

  { Castling rights and move classification as real sets. }
  TCastleRight  = (crWK, crWQ, crBK, crBQ);
  TCastleRights = set of TCastleRight;

  TMoveFlag  = (mfCapture, mfDoublePush, mfEnPassant, mfCastleK, mfCastleQ, mfPromo);
  TMoveFlags = set of TMoveFlag;

  TMove = record
    fromSq, toSq: Integer;
    promo:        TPieceKind;   { pkNone unless a promotion }
    flags:        TMoveFlags;
  end;

  TPosition = record
    board:      array[0..63] of TPiece;
    sideToMove: TColor;
    castling:   TCastleRights;
    epSquare:   Integer;        { en-passant target square, -1 if none }
    hash:       UInt64;
  end;

  TUndo = record
    move:        TMove;
    captured:    TPiece;
    prevCastle:  TCastleRights;
    prevEP:      Integer;
    prevHash:    UInt64;
  end;

  { Procedural type: evaluation is a sum of independent term functions held in
    a table, so terms can be added/swapped without touching the search. }
  TEvalTerm = function(const pos: TPosition): Integer;

  TTFlag = (ttExact, ttLower, ttUpper);

  TTEntry = record
    key:   UInt64;
    depth: Integer;
    score: Integer;
    flag:  TTFlag;
    used:  Boolean;
  end;

  EChess = class(Exception);

{ ---- Globals: Zobrist keys + transposition table ---- }

var
  zPiece:   array[cWhite..cBlack, pkPawn..pkKing, 0..63] of UInt64;
  zSide:    UInt64;
  zCastle:  array[crWK..crBQ] of UInt64;
  zEPFile:  array[0..7] of UInt64;
  tt:       array[0..TT_SIZE - 1] of TTEntry;
  EvalTerms: array[0..2] of TEvalTerm;

{ ===== Square helpers ===== }

function FileOf(sq: Integer): Integer; begin FileOf := sq and 7; end;
function RankOf(sq: Integer): Integer; begin RankOf := sq shr 3; end;
function SquareOf(f, r: Integer): Integer; begin SquareOf := r * 8 + f; end;

function SquareName(sq: Integer): AnsiString;
begin
  SquareName := Chr(Ord('a') + FileOf(sq)) + Chr(Ord('1') + RankOf(sq));
end;

function Opp(c: TColor): TColor;
begin
  if c = cWhite then Opp := cBlack else Opp := cWhite;
end;

{ ===== Zobrist (UInt64 stress, splitmix64 keyed) ===== }

var zState: UInt64;

function NextKey: UInt64;
var z: UInt64;
begin
  zState := zState + UInt64($9E3779B97F4A7C15);
  z := zState;
  z := (z xor (z shr 30)) * UInt64($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * UInt64($94D049BB133111EB);
  NextKey := z xor (z shr 31);
end;

procedure InitZobrist;
var c: TColor; k: TPieceKind; sq, f: Integer; cr: TCastleRight;
begin
  zState := UInt64($0123456789ABCDEF);
  for c := cWhite to cBlack do
    for k := pkPawn to pkKing do
      for sq := 0 to 63 do
        zPiece[c, k, sq] := NextKey;
  zSide := NextKey;
  for cr := crWK to crBQ do zCastle[cr] := NextKey;
  for f := 0 to 7 do zEPFile[f] := NextKey;
end;

function ComputeHash(const pos: TPosition): UInt64;
var sq: Integer; h: UInt64; cr: TCastleRight;
begin
  h := 0;
  for sq := 0 to 63 do
    if pos.board[sq].kind <> pkNone then
      h := h xor zPiece[pos.board[sq].color, pos.board[sq].kind, sq];
  if pos.sideToMove = cBlack then h := h xor zSide;
  for cr := crWK to crBQ do
    if cr in pos.castling then h := h xor zCastle[cr];
  if pos.epSquare >= 0 then h := h xor zEPFile[FileOf(pos.epSquare)];
  ComputeHash := h;
end;

{ ===== FEN parsing (managed strings + exceptions) ===== }

procedure ClearBoard(var pos: TPosition);
var sq: Integer;
begin
  for sq := 0 to 63 do
  begin
    pos.board[sq].kind := pkNone;
    pos.board[sq].color := cWhite;
  end;
  pos.castling := [];
  pos.epSquare := -1;
  pos.sideToMove := cWhite;
end;

procedure PieceFromChar(c: Char; var pc: TPiece; var ok: Boolean);
begin
  ok := True;
  if (c >= 'a') and (c <= 'z') then pc.color := cBlack
  else pc.color := cWhite;
  case UpCase(c) of
    'P': pc.kind := pkPawn;
    'N': pc.kind := pkKnight;
    'B': pc.kind := pkBishop;
    'R': pc.kind := pkRook;
    'Q': pc.kind := pkQueen;
    'K': pc.kind := pkKing;
  else
    ok := False;
  end;
end;

procedure SetFEN(var pos: TPosition; const fen: AnsiString);
var i, f, r, sq, n: Integer; c: Char; pc: TPiece; ok: Boolean; field: Integer;
begin
  ClearBoard(pos);
  field := 0;
  i := 1;
  f := 0; r := 7;   { FEN starts at rank 8 (top), file a }

  { field 0: piece placement }
  while (i <= Length(fen)) and (fen[i] <> ' ') do
  begin
    c := fen[i];
    if c = '/' then
    begin
      r := r - 1; f := 0;
    end
    else if (c >= '1') and (c <= '8') then
      f := f + (Ord(c) - Ord('0'))
    else
    begin
      PieceFromChar(c, pc, ok);
      if not ok then raise EChess.Create('bad piece in FEN: ' + c);
      if (r < 0) or (f > 7) then raise EChess.Create('FEN board overflow');
      sq := SquareOf(f, r);
      pos.board[sq] := pc;
      f := f + 1;
    end;
    i := i + 1;
  end;

  { field 1: side to move }
  while (i <= Length(fen)) and (fen[i] = ' ') do i := i + 1;
  if (i <= Length(fen)) and (fen[i] = 'b') then pos.sideToMove := cBlack
  else pos.sideToMove := cWhite;
  while (i <= Length(fen)) and (fen[i] <> ' ') do i := i + 1;

  { field 2: castling rights }
  while (i <= Length(fen)) and (fen[i] = ' ') do i := i + 1;
  while (i <= Length(fen)) and (fen[i] <> ' ') do
  begin
    case fen[i] of
      'K': pos.castling := pos.castling + [crWK];
      'Q': pos.castling := pos.castling + [crWQ];
      'k': pos.castling := pos.castling + [crBK];
      'q': pos.castling := pos.castling + [crBQ];
    end;
    i := i + 1;
  end;

  { field 3: en-passant target }
  while (i <= Length(fen)) and (fen[i] = ' ') do i := i + 1;
  if (i <= Length(fen)) and (fen[i] >= 'a') and (fen[i] <= 'h') then
  begin
    f := Ord(fen[i]) - Ord('a');
    n := Ord(fen[i + 1]) - Ord('1');
    pos.epSquare := SquareOf(f, n);
  end;

  pos.hash := ComputeHash(pos);
end;

{ ===== Attack detection ===== }

function OnBoardStep(var sq: Integer; df, dr: Integer): Boolean;
{ Advance sq by (df,dr) on the 8x8 mailbox; False if it falls off the edge. }
var f, r: Integer;
begin
  f := FileOf(sq) + df;
  r := RankOf(sq) + dr;
  if (f < 0) or (f > 7) or (r < 0) or (r > 7) then
    OnBoardStep := False
  else
  begin
    sq := SquareOf(f, r);
    OnBoardStep := True;
  end;
end;

const
  KnightDF: array[0..7] of Integer = ( 1,  2,  2,  1, -1, -2, -2, -1);
  KnightDR: array[0..7] of Integer = ( 2,  1, -1, -2, -2, -1,  1,  2);
  KingDF:   array[0..7] of Integer = ( 1,  1,  0, -1, -1, -1,  0,  1);
  KingDR:   array[0..7] of Integer = ( 0,  1,  1,  1,  0, -1, -1, -1);
  { rook/bishop ray directions }
  RookDF:   array[0..3] of Integer = ( 1, -1,  0,  0);
  RookDR:   array[0..3] of Integer = ( 0,  0,  1, -1);
  BishopDF: array[0..3] of Integer = ( 1,  1, -1, -1);
  BishopDR: array[0..3] of Integer = ( 1, -1,  1, -1);

function SlideAttack(const pos: TPosition; from: Integer;
                     const df, dr: array of Integer; kind: TPieceKind;
                     attacker: TColor): Boolean;
var d, sq: Integer;
begin
  SlideAttack := False;
  for d := 0 to High(df) do
  begin
    sq := from;
    while OnBoardStep(sq, df[d], dr[d]) do
    begin
      if pos.board[sq].kind <> pkNone then
      begin
        if (pos.board[sq].color = attacker) and
           ((pos.board[sq].kind = kind) or (pos.board[sq].kind = pkQueen)) then
        begin
          SlideAttack := True;
          Exit;
        end;
        Break;   { ray blocked }
      end;
    end;
  end;
end;

function IsAttacked(const pos: TPosition; target: Integer; by: TColor): Boolean;
var d, sq: Integer; pdir: Integer;
begin
  IsAttacked := True;

  { knights }
  for d := 0 to 7 do
  begin
    sq := target;
    if OnBoardStep(sq, KnightDF[d], KnightDR[d]) then
      if (pos.board[sq].kind = pkKnight) and (pos.board[sq].color = by) then Exit;
  end;

  { king }
  for d := 0 to 7 do
  begin
    sq := target;
    if OnBoardStep(sq, KingDF[d], KingDR[d]) then
      if (pos.board[sq].kind = pkKing) and (pos.board[sq].color = by) then Exit;
  end;

  { pawns — a pawn of color `by` attacks diagonally toward the target }
  if by = cWhite then pdir := -1 else pdir := 1;   { from target's view }
  sq := target;
  if OnBoardStep(sq, 1, pdir) then
    if (pos.board[sq].kind = pkPawn) and (pos.board[sq].color = by) then Exit;
  sq := target;
  if OnBoardStep(sq, -1, pdir) then
    if (pos.board[sq].kind = pkPawn) and (pos.board[sq].color = by) then Exit;

  { sliding: rook/queen orthogonally, bishop/queen diagonally }
  if SlideAttack(pos, target, RookDF, RookDR, pkRook, by) then Exit;
  if SlideAttack(pos, target, BishopDF, BishopDR, pkBishop, by) then Exit;

  IsAttacked := False;
end;

function KingSquare(const pos: TPosition; c: TColor): Integer;
var sq: Integer;
begin
  KingSquare := -1;
  for sq := 0 to 63 do
    if (pos.board[sq].kind = pkKing) and (pos.board[sq].color = c) then
    begin
      KingSquare := sq;
      Exit;
    end;
end;

function InCheck(const pos: TPosition; c: TColor): Boolean;
begin
  InCheck := IsAttacked(pos, KingSquare(pos, c), Opp(c));
end;

{ ===== Make / unmake ===== }

procedure MakeMove(var pos: TPosition; const m: TMove; var u: TUndo);
var us, them: TColor; movd: TPiece; capSq: Integer;
begin
  u.move := m;
  u.captured := pos.board[m.toSq];
  u.prevCastle := pos.castling;
  u.prevEP := pos.epSquare;
  u.prevHash := pos.hash;

  us := pos.sideToMove;
  them := Opp(us);
  movd := pos.board[m.fromSq];

  { en-passant captures a pawn that is not on toSq }
  if mfEnPassant in m.flags then
  begin
    if us = cWhite then capSq := m.toSq - 8 else capSq := m.toSq + 8;
    pos.board[capSq].kind := pkNone;
  end;

  { move the piece (promotion replaces the kind) }
  pos.board[m.fromSq].kind := pkNone;
  if mfPromo in m.flags then movd.kind := m.promo;
  pos.board[m.toSq] := movd;

  { rook hop on castling }
  if mfCastleK in m.flags then
  begin
    pos.board[m.toSq + 1].kind := pkNone;
    pos.board[m.toSq - 1] := movd;            { placeholder color; fix kind }
    pos.board[m.toSq - 1].kind := pkRook;
    pos.board[m.toSq - 1].color := us;
  end
  else if mfCastleQ in m.flags then
  begin
    pos.board[m.toSq - 2].kind := pkNone;
    pos.board[m.toSq + 1].kind := pkRook;
    pos.board[m.toSq + 1].color := us;
  end;

  { update castling rights when king/rook move or rook captured }
  if movd.kind = pkKing then
  begin
    if us = cWhite then pos.castling := pos.castling - [crWK, crWQ]
    else pos.castling := pos.castling - [crBK, crBQ];
  end;
  if m.fromSq = SquareOf(7, 0) then pos.castling := pos.castling - [crWK];
  if m.fromSq = SquareOf(0, 0) then pos.castling := pos.castling - [crWQ];
  if m.fromSq = SquareOf(7, 7) then pos.castling := pos.castling - [crBK];
  if m.fromSq = SquareOf(0, 7) then pos.castling := pos.castling - [crBQ];
  if m.toSq = SquareOf(7, 0) then pos.castling := pos.castling - [crWK];
  if m.toSq = SquareOf(0, 0) then pos.castling := pos.castling - [crWQ];
  if m.toSq = SquareOf(7, 7) then pos.castling := pos.castling - [crBK];
  if m.toSq = SquareOf(0, 7) then pos.castling := pos.castling - [crBQ];

  { set en-passant target on a double push }
  pos.epSquare := -1;
  if mfDoublePush in m.flags then
  begin
    if us = cWhite then pos.epSquare := m.toSq - 8 else pos.epSquare := m.toSq + 8;
  end;

  pos.sideToMove := them;
  pos.hash := ComputeHash(pos);   { simple full recompute — correctness over speed }
end;

procedure UnmakeMove(var pos: TPosition; const u: TUndo);
var m: TMove; us: TColor; movd: TPiece; capSq: Integer;
begin
  m := u.move;
  pos.sideToMove := Opp(pos.sideToMove);
  us := pos.sideToMove;

  movd := pos.board[m.toSq];
  if mfPromo in m.flags then movd.kind := pkPawn;   { demote back }

  pos.board[m.fromSq] := movd;
  pos.board[m.toSq] := u.captured;

  if mfEnPassant in m.flags then
  begin
    pos.board[m.toSq].kind := pkNone;              { toSq was empty }
    if us = cWhite then capSq := m.toSq - 8 else capSq := m.toSq + 8;
    pos.board[capSq].kind := pkPawn;
    pos.board[capSq].color := Opp(us);
  end;

  if mfCastleK in m.flags then
  begin
    pos.board[m.toSq + 1] := movd;
    pos.board[m.toSq + 1].kind := pkRook;
    pos.board[m.toSq - 1].kind := pkNone;
  end
  else if mfCastleQ in m.flags then
  begin
    pos.board[m.toSq - 2] := movd;
    pos.board[m.toSq - 2].kind := pkRook;
    pos.board[m.toSq + 1].kind := pkNone;
  end;

  pos.castling := u.prevCastle;
  pos.epSquare := u.prevEP;
  pos.hash := u.prevHash;
end;

{ ===== Move generation as a generator (yield + for-in) ===== }

function MkMove(from, dest: Integer; promo: TPieceKind; flags: TMoveFlags): TMove;
begin
  MkMove.fromSq := from;
  MkMove.toSq := dest;
  MkMove.promo := promo;
  MkMove.flags := flags;
end;

function GenMoves(const pos: TPosition): TMove; generator;
{ Pseudo-legal moves for the side to move. Legality (own king safe) is filtered
  by the caller via make / InCheck / unmake. }
var
  from, dest, d, startRank, promoRank, dir: Integer;
  us, them: TColor;
  k: TPieceKind;
begin
  us := pos.sideToMove;
  them := Opp(us);
  if us = cWhite then begin dir := 8; startRank := 1; promoRank := 7; end
  else begin dir := -8; startRank := 6; promoRank := 0; end;

  for from := 0 to 63 do
  begin
    if pos.board[from].kind = pkNone then continue;
    if pos.board[from].color <> us then continue;
    k := pos.board[from].kind;

    case k of
      pkPawn:
      begin
        { single push (with promotion expansion), then double push }
        dest := from + dir;
        if (dest >= 0) and (dest <= 63) and (pos.board[dest].kind = pkNone) then
        begin
          if RankOf(dest) = promoRank then
          begin
            yield MkMove(from, dest, pkQueen,  [mfPromo]);
            yield MkMove(from, dest, pkRook,   [mfPromo]);
            yield MkMove(from, dest, pkBishop, [mfPromo]);
            yield MkMove(from, dest, pkKnight, [mfPromo]);
          end
          else
          begin
            yield MkMove(from, dest, pkNone, []);
            if RankOf(from) = startRank then
            begin
              dest := from + 2 * dir;
              if pos.board[dest].kind = pkNone then
                yield MkMove(from, dest, pkNone, [mfDoublePush]);
            end;
          end;
        end;
        { diagonal captures, including en-passant and promotion-on-capture }
        for d := -1 to 1 do
          if d <> 0 then
          begin
            dest := from;
            if OnBoardStep(dest, d, dir div 8) then
            begin
              if (pos.board[dest].kind <> pkNone) and (pos.board[dest].color = them) then
              begin
                if RankOf(dest) = promoRank then
                begin
                  yield MkMove(from, dest, pkQueen,  [mfCapture, mfPromo]);
                  yield MkMove(from, dest, pkRook,   [mfCapture, mfPromo]);
                  yield MkMove(from, dest, pkBishop, [mfCapture, mfPromo]);
                  yield MkMove(from, dest, pkKnight, [mfCapture, mfPromo]);
                end
                else
                  yield MkMove(from, dest, pkNone, [mfCapture]);
              end
              else if dest = pos.epSquare then
                yield MkMove(from, dest, pkNone, [mfEnPassant, mfCapture]);
            end;
          end;
      end;

      pkKnight:
        for d := 0 to 7 do
        begin
          dest := from;
          if OnBoardStep(dest, KnightDF[d], KnightDR[d]) then
            if (pos.board[dest].kind = pkNone) then
              yield MkMove(from, dest, pkNone, [])
            else if pos.board[dest].color = them then
              yield MkMove(from, dest, pkNone, [mfCapture]);
        end;

      pkKing:
      begin
        for d := 0 to 7 do
        begin
          dest := from;
          if OnBoardStep(dest, KingDF[d], KingDR[d]) then
            if (pos.board[dest].kind = pkNone) then
              yield MkMove(from, dest, pkNone, [])
            else if pos.board[dest].color = them then
              yield MkMove(from, dest, pkNone, [mfCapture]);
        end;
        { castling: rights + empty squares + king not passing through attack }
        if us = cWhite then
        begin
          if (crWK in pos.castling) and (pos.board[5].kind = pkNone) and
             (pos.board[6].kind = pkNone) and not IsAttacked(pos, 4, them) and
             not IsAttacked(pos, 5, them) and not IsAttacked(pos, 6, them) then
            yield MkMove(4, 6, pkNone, [mfCastleK]);
          if (crWQ in pos.castling) and (pos.board[3].kind = pkNone) and
             (pos.board[2].kind = pkNone) and (pos.board[1].kind = pkNone) and
             not IsAttacked(pos, 4, them) and not IsAttacked(pos, 3, them) and
             not IsAttacked(pos, 2, them) then
            yield MkMove(4, 2, pkNone, [mfCastleQ]);
        end
        else
        begin
          if (crBK in pos.castling) and (pos.board[61].kind = pkNone) and
             (pos.board[62].kind = pkNone) and not IsAttacked(pos, 60, them) and
             not IsAttacked(pos, 61, them) and not IsAttacked(pos, 62, them) then
            yield MkMove(60, 62, pkNone, [mfCastleK]);
          if (crBQ in pos.castling) and (pos.board[59].kind = pkNone) and
             (pos.board[58].kind = pkNone) and (pos.board[57].kind = pkNone) and
             not IsAttacked(pos, 60, them) and not IsAttacked(pos, 59, them) and
             not IsAttacked(pos, 58, them) then
            yield MkMove(60, 58, pkNone, [mfCastleQ]);
        end;
      end;
    else
      { sliders: bishop / rook / queen share the ray walk }
      begin
        for d := 0 to 3 do
        begin
          { bishop and queen use diagonals }
          if (k = pkBishop) or (k = pkQueen) then
          begin
            dest := from;
            while OnBoardStep(dest, BishopDF[d], BishopDR[d]) do
            begin
              if pos.board[dest].kind = pkNone then
                yield MkMove(from, dest, pkNone, [])
              else
              begin
                if pos.board[dest].color = them then
                  yield MkMove(from, dest, pkNone, [mfCapture]);
                Break;
              end;
            end;
          end;
          { rook and queen use orthogonals }
          if (k = pkRook) or (k = pkQueen) then
          begin
            dest := from;
            while OnBoardStep(dest, RookDF[d], RookDR[d]) do
            begin
              if pos.board[dest].kind = pkNone then
                yield MkMove(from, dest, pkNone, [])
              else
              begin
                if pos.board[dest].color = them then
                  yield MkMove(from, dest, pkNone, [mfCapture]);
                Break;
              end;
            end;
          end;
        end;
      end;
    end;
  end;
end;

{ ===== Perft (the deterministic oracle) ===== }

function Perft(var pos: TPosition; depth: Integer): Int64;
var u: TUndo; us: TColor; nodes: Int64; m: TMove;
begin
  if depth = 0 then
  begin
    Perft := 1;
    Exit;
  end;
  nodes := 0;
  us := pos.sideToMove;
  for m in GenMoves(pos) do
  begin
    MakeMove(pos, m, u);
    if not InCheck(pos, us) then        { the side that just moved must be safe }
      nodes := nodes + Perft(pos, depth - 1);
    UnmakeMove(pos, u);
  end;
  Perft := nodes;
end;

{ ===== Evaluation: a table of procedural-typed terms ===== }

const
  PieceValue: array[pkNone..pkKing] of Integer =
    (0, 100, 320, 330, 500, 900, 0);

  { one piece-square table, white's view (pawn), to show const 2-D data }
  PawnPST: array[0..63] of Integer = (
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10,-20,-20, 10, 10,  5,
     5, -5,-10,  0,  0,-10, -5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5,  5, 10, 25, 25, 10,  5,  5,
    10, 10, 20, 30, 30, 20, 10, 10,
    50, 50, 50, 50, 50, 50, 50, 50,
     0,  0,  0,  0,  0,  0,  0,  0);

function TermMaterial(const pos: TPosition): Integer;
var sq, s: Integer;
begin
  s := 0;
  for sq := 0 to 63 do
    if pos.board[sq].kind <> pkNone then
    begin
      if pos.board[sq].color = cWhite then s := s + PieceValue[pos.board[sq].kind]
      else s := s - PieceValue[pos.board[sq].kind];
    end;
  TermMaterial := s;
end;

function TermPawnPlacement(const pos: TPosition): Integer;
var sq, s: Integer;
begin
  s := 0;
  for sq := 0 to 63 do
    if pos.board[sq].kind = pkPawn then
    begin
      if pos.board[sq].color = cWhite then s := s + PawnPST[sq]
      else s := s - PawnPST[63 - sq];   { mirror for black }
    end;
  TermPawnPlacement := s;
end;

function TermTempo(const pos: TPosition): Integer;
begin
  { tiny side-to-move bonus }
  if pos.sideToMove = cWhite then TermTempo := 10 else TermTempo := -10;
end;

function Evaluate(const pos: TPosition): Integer;
var i, s: Integer;
begin
  s := 0;
  for i := 0 to High(EvalTerms) do
    s := s + EvalTerms[i](pos);          { indirect call through proc-typed table }
  { negamax wants score from the side-to-move's perspective }
  if pos.sideToMove = cWhite then Evaluate := s else Evaluate := -s;
end;

{ ===== Engine class (VMT + an overriding descendant) ===== }

type
  TEngine = class
  public
    pos: TPosition;
    nodes: Int64;
    constructor Create;
    procedure NewGame;
    function ScorePosition: Integer; virtual;   { overridable eval hook }
    function Search(depth, alpha, beta: Integer): Integer;
    function BestMove(depth: Integer; var best: TMove): Integer;
  end;

  { A descendant that biases toward material — shows virtual dispatch. }
  TGreedyEngine = class(TEngine)
  public
    function ScorePosition: Integer; override;
  end;

constructor TEngine.Create;
begin
  nodes := 0;
end;

procedure TEngine.NewGame;
begin
  SetFEN(pos, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
end;

function TEngine.ScorePosition: Integer;
begin
  ScorePosition := Evaluate(pos);
end;

function TGreedyEngine.ScorePosition: Integer;
begin
  { weight material twice, ignore positional terms }
  ScorePosition := 2 * TermMaterial(pos);
  if pos.sideToMove = cBlack then ScorePosition := -ScorePosition;
end;

function TEngine.Search(depth, alpha, beta: Integer): Integer;
var
  u: TUndo; us: TColor; m: TMove; score, best, idx: Integer;
  anyLegal: Boolean; e: TTEntry;
begin
  Inc(nodes);

  { transposition probe }
  idx := Integer(pos.hash mod UInt64(TT_SIZE));
  e := tt[idx];
  if e.used and (e.key = pos.hash) and (e.depth >= depth) then
  begin
    if e.flag = ttExact then begin Search := e.score; Exit; end;
    if (e.flag = ttLower) and (e.score > alpha) then alpha := e.score;
    if (e.flag = ttUpper) and (e.score < beta) then beta := e.score;
    if alpha >= beta then begin Search := e.score; Exit; end;
  end;

  if depth = 0 then
  begin
    Search := ScorePosition;     { virtual — descendant can override }
    Exit;
  end;

  us := pos.sideToMove;
  best := -INF;
  anyLegal := False;

  for m in GenMoves(pos) do
  begin
    MakeMove(pos, m, u);
    if InCheck(pos, us) then
    begin
      UnmakeMove(pos, u);
      continue;
    end;
    anyLegal := True;
    score := -Search(depth - 1, -beta, -alpha);
    UnmakeMove(pos, u);

    if score > best then best := score;
    if best > alpha then alpha := best;
    if alpha >= beta then Break;     { beta cutoff }
  end;

  if not anyLegal then
  begin
    { no legal move: checkmate (bad) or stalemate (draw) }
    if InCheck(pos, us) then best := -MATE + (100 - depth)
    else best := 0;
  end;

  { store }
  e.key := pos.hash;
  e.depth := depth;
  e.score := best;
  e.used := True;
  if best <= alpha then e.flag := ttUpper
  else if best >= beta then e.flag := ttLower
  else e.flag := ttExact;
  tt[idx] := e;

  Search := best;
end;

function TEngine.BestMove(depth: Integer; var best: TMove): Integer;
var u: TUndo; us: TColor; m: TMove; score, bestScore: Integer; found: Boolean;
begin
  us := pos.sideToMove;
  bestScore := -INF;
  found := False;
  for m in GenMoves(pos) do
  begin
    MakeMove(pos, m, u);
    if not InCheck(pos, us) then
    begin
      score := -Search(depth - 1, -INF, INF);
      if (not found) or (score > bestScore) then
      begin
        bestScore := score;
        best := m;
        found := True;
      end;
    end;
    UnmakeMove(pos, u);
  end;
  BestMove := bestScore;
end;

{ ===== Rendering + move text ===== }

function PieceGlyph(const pc: TPiece): Char;
const W: array[pkNone..pkKing] of Char = ('.', 'P', 'N', 'B', 'R', 'Q', 'K');
      B: array[pkNone..pkKing] of Char = ('.', 'p', 'n', 'b', 'r', 'q', 'k');
begin
  if pc.color = cWhite then PieceGlyph := W[pc.kind] else PieceGlyph := B[pc.kind];
end;

procedure PrintBoard(const pos: TPosition);
var r, f: Integer; line: AnsiString;
begin
  writeln;
  for r := 7 downto 0 do
  begin
    line := Chr(Ord('1') + r) + ' ';
    for f := 0 to 7 do
      line := line + ' ' + PieceGlyph(pos.board[SquareOf(f, r)]);
    writeln(line);
  end;
  writeln('   a b c d e f g h');
  if pos.sideToMove = cWhite then writeln('White to move')
  else writeln('Black to move');
end;

function MoveText(const m: TMove): AnsiString;
const Promo: array[pkNone..pkKing] of Char = (' ', ' ', 'n', 'b', 'r', 'q', ' ');
begin
  MoveText := SquareName(m.fromSq) + SquareName(m.toSq);
  if mfPromo in m.flags then MoveText := MoveText + Promo[m.promo];
end;

{ ===== UCI-ish REPL (managed-string parsing; serial-console friendly) ===== }

procedure SplitFirst(const s: AnsiString; var head, tail: AnsiString);
var i: Integer;
begin
  i := 1;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  head := '';
  while (i <= Length(s)) and (s[i] <> ' ') do begin head := head + s[i]; i := i + 1; end;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  tail := Copy(s, i, Length(s) - i + 1);
end;

procedure Repl(eng: TEngine);
var line, cmd, arg: AnsiString; running: Boolean; m: TMove; sc, n: Integer;
begin
  running := True;
  while running do
  begin
    write('chess> ');
    if Eof then Break;
    readln(line);
    SplitFirst(line, cmd, arg);
    if cmd = 'quit' then running := False
    else if cmd = 'print' then PrintBoard(eng.pos)
    else if cmd = 'fen' then
    begin
      try
        SetFEN(eng.pos, arg);
        PrintBoard(eng.pos);
      except
        on E: EChess do writeln('error: ', E.Message);
      end;
    end
    else if cmd = 'perft' then
    begin
      n := StrToInt(arg);
      writeln('perft(', n, ') = ', Perft(eng.pos, n));
    end
    else if cmd = 'go' then
    begin
      n := StrToInt(arg);
      eng.nodes := 0;
      sc := eng.BestMove(n, m);
      writeln('bestmove ', MoveText(m), '  score ', sc, '  nodes ', eng.nodes);
    end
    else if cmd <> '' then
      writeln('commands: print | fen <FEN> | perft <n> | go <depth> | quit');
  end;
end;

{ ===== Main ===== }

var
  eng: TEngine;
  d: Integer;
  best: TMove;
  score: Integer;
begin
  InitZobrist;

  { wire the procedural-typed evaluation table }
  EvalTerms[0] := @TermMaterial;
  EvalTerms[1] := @TermPawnPlacement;
  EvalTerms[2] := @TermTempo;

  eng := TEngine.Create;
  eng.NewGame;

  writeln('PXX chess demo');
  PrintBoard(eng.pos);

  { deterministic oracle: perft from the start position }
  writeln;
  for d := 1 to 4 do
    writeln('perft(', d, ') = ', Perft(eng.pos, d));

  { fixed-depth best move (search + eval + TT exercised) }
  eng.nodes := 0;
  score := eng.BestMove(4, best);
  writeln;
  writeln('bestmove ', MoveText(best), '  score ', score, '  nodes ', eng.nodes);

  { interactive surface (reads stdin; ends at EOF) }
  Repl(eng);

  eng.Free;
end.
