program test_dynarray_managed_field_reassign;

{ Regression for bug-dynarray-managed-record-field-reassign: assigning a LOCAL
  dynamic array of a managed-field record to a class field must retain the new
  handle and release the old one (ARC), not just copy the handle. Without the
  retain, the local's scope-exit release frees the data the field now points at,
  so the managed strings come back empty (and a shrinking rebuild segfaults). }

type
  TRec = record Cap: AnsiString; P: Integer; end;
  TBag = class
    Items: array of TRec;
    Cnt: Integer;
    procedure Add(const c: AnsiString);
    procedure Shrink;
    procedure DropFirst;
  end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

procedure TBag.Add(const c: AnsiString);
begin SetLength(Items, Cnt + 1); Items[Cnt].Cap := c; Items[Cnt].P := Cnt; Inc(Cnt); end;

procedure TBag.Shrink;            { rebuild same length via a local, reassign }
var tmp: array of TRec; i, n: Integer;
begin
  SetLength(tmp, Cnt); n := 0;
  for i := 0 to Cnt - 1 do begin tmp[n] := Items[i]; Inc(n); end;
  Items := tmp;
  Cnt := n;
end;

procedure TBag.DropFirst;         { shrinking rebuild (fewer survivors) }
var tmp: array of TRec; i, n: Integer;
begin
  SetLength(tmp, Cnt - 1); n := 0;
  for i := 1 to Cnt - 1 do begin tmp[n] := Items[i]; Inc(n); end;
  Items := tmp;
  Cnt := n;
end;

var b: TBag;
begin
  b := TBag.Create;
  b.Add('aa'); b.Add('bb'); b.Add('cc'); b.Add('dd');

  b.Shrink;  Check(b.Items[0].Cap = 'aa');    { survives one reassign }
  b.Shrink;  Check(b.Items[0].Cap = 'aa');    { ... and a second (was empty) }
  b.Shrink;  Check(b.Items[3].Cap = 'dd');

  b.DropFirst; Check((b.Cnt = 3) and (b.Items[0].Cap = 'bb'));  { shrink, was segfault }
  b.DropFirst; Check((b.Cnt = 2) and (b.Items[0].Cap = 'cc'));
  b.DropFirst; Check((b.Cnt = 1) and (b.Items[0].Cap = 'dd'));
end.
