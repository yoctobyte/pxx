{ Embedded resources: turn each pending R-directive (name + file) into bytes in
  Data plus a runtime-walkable table. Mirrors the RTTI registry mechanism
  (EmitRTTI). The table is reached at runtime via the __resources intrinsic
  (DataRef sentinel -101, patched to ResourceTableOff after parse). }

procedure EmitResources;
var
  i, j, len, strIdx, entryPos: Integer;
  nameOff:  array[0..MAX_RESOURCES-1] of Integer;
  blobOff:  array[0..MAX_RESOURCES-1] of Integer;
  blobLen:  array[0..MAX_RESOURCES-1] of Integer;
  path, buf: AnsiString;
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
    strIdx := InternStr(ResPendName[i]);
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
