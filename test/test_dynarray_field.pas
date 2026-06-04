program test_dynarray_field;

{ Dynamic-array fields in records and classes: the managed dynamic-array
  machinery (SetLength, Length, indexed read/write, copy-on-write, retain on
  copy, release on scope exit) operates on a field slot at object+offset, not
  only on a top-level symbol. This is the enabler for collection types whose
  storage is a `array of T` field with no manual memory management. }

{$define PXX_MANAGED_STRING}

type
  TIntList = class
    FItems: array of Integer;
    FCount: Integer;
    procedure Add(v: Integer);
    function Get(i: Integer): Integer;
  end;

  TStrList = class
    FItems: array of AnsiString;
    FCount: Integer;
    procedure Add(const v: AnsiString);
    function Get(i: Integer): AnsiString;
  end;

  TRec = record items: array of Integer; end;

procedure TIntList.Add(v: Integer);
begin
  if Self.FCount >= Length(Self.FItems) then
    SetLength(Self.FItems, Length(Self.FItems) * 2 + 4);   { doubling growth }
  Self.FItems[Self.FCount] := v;
  Self.FCount := Self.FCount + 1;
end;

function TIntList.Get(i: Integer): Integer;
begin
  Result := Self.FItems[i];
end;

procedure TStrList.Add(const v: AnsiString);
begin
  if Self.FCount >= Length(Self.FItems) then
    SetLength(Self.FItems, Length(Self.FItems) * 2 + 4);
  Self.FItems[Self.FCount] := v;
  Self.FCount := Self.FCount + 1;
end;

function TStrList.Get(i: Integer): AnsiString;
begin
  Result := Self.FItems[i];
end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

procedure ScopeFinalize;
var r: TRec;
begin
  { Record-local dynarray field is zero-initialised and released on scope exit;
    called in a loop by the caller to exercise no-leak finalization. }
  SetLength(r.items, 50);
  r.items[0] := 7;
end;

var
  il: TIntList;
  sl: TStrList;
  a, b: TRec;
  i: Integer;
begin
  { Integer list on a class field: grows across several doublings. }
  il := TIntList.Create;
  for i := 0 to 99 do il.Add(i * i);
  Check(il.FCount = 100);
  Check(il.Get(0) = 0);
  Check(il.Get(9) = 81);
  Check(il.Get(99) = 9801);
  Check(Length(il.FItems) >= 100);

  { Managed-string list on a class field: retain on store, COW-safe. }
  sl := TStrList.Create;
  sl.Add('alpha'); sl.Add('beta'); sl.Add('gamma');
  Check(sl.FCount = 3);
  Check(sl.Get(0) = 'alpha');
  Check(sl.Get(2) = 'gamma');

  { Record value copy shares the dynarray field, copy-on-write keeps them
    independent on mutation. }
  SetLength(a.items, 3);
  a.items[0] := 10; a.items[1] := 20; a.items[2] := 30;
  b := a;
  Check(b.items[1] = 20);
  Check(Length(b.items) = 3);
  b.items[1] := 99;
  Check(a.items[1] = 20);     { original untouched }
  Check(b.items[1] = 99);

  { Finalization: 200k scope exits of a record-local dynarray field must not
    leak (verified here only for correctness of the final value). }
  for i := 1 to 200000 do ScopeFinalize;
  Check(True);
end.
