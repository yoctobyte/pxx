program lib_g2048;
{ 2048 engine test: exhaustive SlideLine compress/merge cases, plus deterministic
  move / game-over checks on positions built with ClearBoard/PutTile. }

uses g2048;

var fails: Integer;

procedure CKi(const tag: string; got, want: Integer);
begin
  if got = want then writeln(tag, '=ok')
  else begin writeln(tag, '=bad ', got, '/', want); fails := fails + 1; end;
end;

procedure CKb(const tag: string; got: Boolean);
begin
  if got then writeln(tag, '=ok') else begin writeln(tag, '=bad'); fails := fails + 1; end;
end;

{ build a line, slide it, check result cells + score }
procedure Slide(a0, a1, a2, a3: Integer; const tag: string;
                e0, e1, e2, e3, escore: Integer);
var inp, outp: TLine; sc: Integer;
begin
  inp[0] := a0; inp[1] := a1; inp[2] := a2; inp[3] := a3;
  sc := SlideLine(inp, outp);
  if (outp[0] = e0) and (outp[1] = e1) and (outp[2] = e2) and (outp[3] = e3) and (sc = escore) then
    writeln(tag, '=ok')
  else
  begin
    writeln(tag, '=bad [', outp[0], ',', outp[1], ',', outp[2], ',', outp[3], '] sc=', sc);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;

  { ---- SlideLine ---- }
  Slide(2, 2, 4, 0, 'merge-pair',   4, 4, 0, 0, 4);
  Slide(2, 2, 2, 2, 'two-pairs',    4, 4, 0, 0, 8);
  Slide(4, 4, 4, 0, 'triple',       8, 4, 0, 0, 8);
  Slide(0, 0, 0, 2, 'compress',     2, 0, 0, 0, 0);
  Slide(2, 0, 2, 0, 'gap-merge',    4, 0, 0, 0, 4);
  Slide(2, 4, 2, 4, 'no-merge',     2, 4, 2, 4, 0);
  Slide(0, 0, 0, 0, 'empty',        0, 0, 0, 0, 0);
  Slide(8, 8, 8, 8, 'big-pairs',   16,16, 0, 0, 32);
  Slide(2, 2, 2, 0, 'pair-plus',    4, 2, 0, 0, 4);

  { ---- Move on a built board ---- }
  ClearBoard;
  PutTile(0, 0, 2); PutTile(0, 1, 2);     { row 0: 2 2 . . }
  CKb('move-left-changed', Move2048(0));
  CKi('move-left-merge', CellAt(0, 0), 4);
  CKi('move-left-score', Score2048, 4);

  ClearBoard;
  PutTile(3, 3, 2); PutTile(2, 3, 2);     { column 3: rows 2,3 = 2 }
  CKb('move-up-changed', Move2048(2));
  CKi('move-up-merge', CellAt(0, 3), 4);

  { ---- no-op move returns false (full row, no merge, nothing to slide) ---- }
  ClearBoard;
  PutTile(0, 0, 2); PutTile(0, 1, 4); PutTile(0, 2, 2); PutTile(0, 3, 4);
  CKb('noop-left-false', not Move2048(0));

  { ---- game over: full board, no equal neighbours ---- }
  ClearBoard;
  PutTile(0,0,2);  PutTile(0,1,4);  PutTile(0,2,2);  PutTile(0,3,4);
  PutTile(1,0,4);  PutTile(1,1,2);  PutTile(1,2,4);  PutTile(1,3,2);
  PutTile(2,0,2);  PutTile(2,1,4);  PutTile(2,2,2);  PutTile(2,3,4);
  PutTile(3,0,4);  PutTile(3,1,2);  PutTile(3,2,4);  PutTile(3,3,2);
  CKb('game-over', IsOver2048);
  PutTile(3,3,4);                          { now (3,2)=4 and (3,3)=4 adjacent }
  CKb('not-over-after-pair', not IsOver2048);

  { ---- a fresh game has exactly two tiles ---- }
  NewGame2048(1);
  CKb('new-not-over', not IsOver2048);

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
