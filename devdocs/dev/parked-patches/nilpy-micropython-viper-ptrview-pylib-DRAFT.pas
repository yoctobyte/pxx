{ ---- MicroPython viper's ptr8 / ptr16 / ptr32 --------------------------------
  `bitmap = ptr16(buffer)` in a @micropython.viper function: element i is the
  `width` bytes at width*i of the buffer, little-endian (native on every target
  MicroPython and pxx share), read unsigned, written truncated to the width --
  a viper store keeps the low bits, which is what st7789py.py's _pack8 relies on
  to put a 16-bit colour into two bytes. Pure-Python semantics otherwise: the
  index is bounds-checked (viper does not check; an index outside the buffer is
  a program that is already wrong, and IndexError leaves the mistake visible).
  The buffer is retained and released in PyObjFinalize. }
function pyptr_view(const buf: Variant; width: Int64): TPyPtrView;
var o: Pointer;
begin
  o := nil;
  if pyvar_is_objtag(buf) then o := pyvarobj(buf);
  if (o = nil) or not (TObject(o) is TPyBytes) then
    raise TypeError.Create('ptr' + IntToStr(width * 8) + '() needs a bytearray or '
      + 'bytes buffer here; a pointer made from an integer address is not '
      + 'implemented');
  Result := TPyPtrView.Create;
  Result.FBuf := TPyBytes(o);
  Result.FWidth := width;
  PXXObjRetain(o);
end;

function PyPtrOff(v: TPyPtrView; i: Integer): PByte;
begin
  if (i < 0) or (Int64(i) * v.FWidth + v.FWidth > v.FBuf.FLen) then
    raise IndexError.Create('ptr' + IntToStr(v.FWidth * 8) + ' index out of range');
  Result := PByte(NativeInt(v.FBuf.FData) + i * v.FWidth);
end;

function TPyPtrView.at(i: Integer): Int64;
var p: PByte; k: Integer;
begin
  p := PyPtrOff(Self, i);
  Result := 0;
  for k := FWidth - 1 downto 0 do
    Result := (Result shl 8) or PByte(NativeInt(p) + k)^;
end;

procedure TPyPtrView.put(i: Integer; v: Int64);
var p: PByte; k: Integer;
begin
  p := PyPtrOff(Self, i);
  for k := 0 to FWidth - 1 do
  begin
    PByte(NativeInt(p) + k)^ := Byte(v and $FF);
    v := v shr 8;
  end;
end;

function TPyPtrView.__getitem__(const k: Variant): Variant;
begin
  Result := at(k);
end;

function TPyPtrView.__setitem__(const k, v: Variant): Integer;
begin
  put(k, v);
  Result := 0;
end;
