{ Embedded resources: turn each pending R-directive (name + file) into bytes in
  Data plus a runtime-walkable table. Mirrors the RTTI registry mechanism
  (EmitRTTI). The table is reached at runtime via the __resources intrinsic
  (DataRef sentinel -101, patched to ResourceTableOff after parse). }

function LfmRootClassName(const buf: AnsiString): AnsiString;
{ Extract the root object's class from .lfm text: 'object Form1: TForm1 ...'
  -> 'TForm1'. The first ':' belongs to the root object header (properties use
  '='), so read the identifier following it. Used to name a $R *.lfm resource
  so InitInheritedComponent(Self, ClassName) can find it. }
var i, n: Integer; r: AnsiString; c: Char;
begin
  r := '';
  n := Length(buf);
  i := 1;
  while (i <= n) and (buf[i] <> ':') do Inc(i);
  Inc(i);                                  { past ':' }
  while (i <= n) and ((buf[i] = ' ') or (buf[i] = #9)) do Inc(i);
  while i <= n do
  begin
    c := buf[i];
    if ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z')) or
       ((c >= '0') and (c <= '9')) or (c = '_') then
    begin
      AppendChar(r, c);
      Inc(i);
    end
    else
      Break;
  end;
  LfmRootClassName := r;
end;

procedure EmitResources;
var
  i, j, len, strIdx, entryPos: Integer;
  nameOff:  array[0..MAX_RESOURCES-1] of Integer;
  blobOff:  array[0..MAX_RESOURCES-1] of Integer;
  blobLen:  array[0..MAX_RESOURCES-1] of Integer;
  path, buf, resName: AnsiString;
begin
  ResourceTableOff := -1;
  ResourceCount := 0;
  if ResPendCount = 0 then Exit;

  { Pass 1: emit each blob and its name string into Data, remember offsets. }
  for i := 0 to ResPendCount - 1 do
  begin
    ConcatThree(SourceFileDir, ResPendFile[i], '', path);
    LoadFile(path, buf);
    len := Length(buf);
    if len = 0 then Error('resource file not found or empty: ' + ResPendFile[i]);
    while (DataLen mod 8) <> 0 do DataPutB(0);
    blobOff[i] := DataLen;
    blobLen[i] := len;
    for j := 1 to len do DataPutB(Byte(Ord(buf[j])));
    { Wildcard $R *.lfm leaves the name empty; derive it from the .lfm root
      object's class so InitInheritedComponent(Self, ClassName) resolves it. }
    if Length(ResPendName[i]) = 0 then
      resName := LfmRootClassName(buf)
    else
      resName := ResPendName[i];
    strIdx := InternStr(resName);
    nameOff[i] := Strs[strIdx].Offset;
  end;

  { Pass 2: table = count slot, then (nameptr, dataptr, len) triples. }
  while (DataLen mod 8) <> 0 do DataPutB(0);
  ResourceTableOff := DataLen;
  ResourceCount := ResPendCount;
  DataPutZeros(8);
  PatchDataU64(ResourceTableOff, ResPendCount);
  for i := 0 to ResPendCount - 1 do
  begin
    entryPos := DataLen;
    DataPutZeros(24);                       { nameptr(8), dataptr(8), len(8) }
    AddDataPtrFix(entryPos + 0, nameOff[i]);
    AddDataPtrFix(entryPos + 8, blobOff[i]);
    PatchDataU64(entryPos + 16, blobLen[i]);
  end;
end;
