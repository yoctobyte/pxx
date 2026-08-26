program test_forin_member_temp_zeroinit;

{ `for x in <member access>` materialises the container into a HIDDEN dyn-array
  local (ParseForInNodeAST). That local is minted while the body is parsed —
  after the prologue's managed-local zero-init pass has already run — so it used
  to hold stale stack bytes, and the loop's first store RELEASED that garbage as
  if it were the handle it was replacing. When the bytes happened to be a live
  heap pointer, an object nobody owned lost a refcount.

  The witness is the DirtyFrame call: it leaves a live TItem pointer in the
  stack region SumIds is about to use for that hidden temp. Without it the bug
  is invisible on x86-64 and reproduces only on aarch64, which is how it was
  filed (regression-test-aarch64-test-forin-member-access) — the target was
  never the variable, the frame layout was.

  Reverting the fix must make this print 41 / 41 on EVERY target. }

type
  TItem = class
    Id: Integer;
  end;

  TBag = class
    Items: array of TItem;
  end;

  TGame = class
    Bag: TBag;
    function SumIds: Integer;
  end;

function TGame.SumIds: Integer;
var it: TItem;
begin
  Result := 0;
  for it in Bag.Items do Result := Result + it.Id;
end;

{ Leave a live heap pointer in eight consecutive frame slots. Nothing here is
  contrived about the POINTER — any routine returning over a frame that held one
  does the same; this one just makes the coverage deterministic. }
procedure DirtyFrame(p: TItem);
var q0, q1, q2, q3, q4, q5, q6, q7: Pointer;
begin
  q0 := Pointer(p); q1 := Pointer(p); q2 := Pointer(p); q3 := Pointer(p);
  q4 := Pointer(p); q5 := Pointer(p); q6 := Pointer(p); q7 := Pointer(p);
  if q0 = nil then Writeln('unreachable');
  if q1 = nil then Writeln('unreachable');
  if q2 = nil then Writeln('unreachable');
  if q3 = nil then Writeln('unreachable');
  if q4 = nil then Writeln('unreachable');
  if q5 = nil then Writeln('unreachable');
  if q6 = nil then Writeln('unreachable');
  if q7 = nil then Writeln('unreachable');
end;

var
  g: TGame;
  a, b: TItem;
  outer: Integer;
  it: TItem;
begin
  g := TGame.Create;
  g.Bag := TBag.Create;
  SetLength(g.Bag.Items, 2);
  a := TItem.Create; a.Id := 30; g.Bag.Items[0] := a;
  b := TItem.Create; b.Id := 12; g.Bag.Items[1] := b;

  DirtyFrame(a);
  Writeln(g.SumIds);          { 42 — the method arm (implicit-Self member access) }

  DirtyFrame(b);
  outer := 0;
  for it in g.Bag.Items do outer := outer + it.Id;
  Writeln(outer);             { 42 — the two-level arm, g.Bag.Items }

  { and the objects themselves are untouched: an over-release showed up here as
    a silently decremented field, not as a crash }
  Writeln(a.Id, ' ', b.Id);   { 30 12 }
end.
