{ ===== Emitter ===== }

procedure EmitB(b: Byte); inline;
begin
  if CodeLen >= MAX_CODE then Error('code overflow');
  Code[CodeLen] := b; Inc(CodeLen);
end;

procedure EmitI32(v: Int64);
begin
  EmitB(Byte(v and $FF)); EmitB(Byte((v shr 8) and $FF));
  EmitB(Byte((v shr 16) and $FF)); EmitB(Byte((v shr 24) and $FF));
end;

procedure EmitI64(v: Int64);
begin EmitI32(v and $FFFFFFFF); EmitI32((v shr 32) and $FFFFFFFF); end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos]   := Byte(v and $FF); Code[pos+1] := Byte((v shr 8) and $FF);
  Code[pos+2] := Byte((v shr 16) and $FF); Code[pos+3] := Byte((v shr 24) and $FF);
end;

procedure Patch8(pos: Integer; v: Byte);
begin
  Code[pos] := v;
end;

procedure MovRaxImm(v: Int64); begin EmitB($48); EmitB($B8); EmitI64(v); end;
procedure MovRbxImm(v: Int64); begin EmitB($48); EmitB($BB); EmitI64(v); end;
procedure MovRdiImm(v: Int64); begin EmitB($48); EmitB($BF); EmitI64(v); end;
procedure MovRsiImm(v: Int64); begin EmitB($48); EmitB($BE); EmitI64(v); end;
procedure MovRdxImm(v: Int64); begin EmitB($48); EmitB($BA); EmitI64(v); end;

procedure EmitSyscall; begin EmitB($0F); EmitB($05); end;

procedure EmitDataRef(dataOff: Integer);
{ Absolute data-address placeholder; width follows the target's pointer size
  (writeELF patches 8 bytes, writeELF32 patches 4). }
begin
  if FixCount >= MAX_FIXUPS then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  if TargetArch = TARGET_I386 then EmitI32(0) else EmitI64(0);
end;

procedure EmitGlobRef(bssOff: Integer);
{ Emit 4-byte placeholder for absolute BSS address }
begin
  if GlobFixCount >= MAX_GLOBFIX then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount); EmitI32(0);
end;

procedure EmitwriteSyscall(dataOff, len: Integer);
begin
  if TargetArch = TARGET_I386 then
  begin
    { i386 int 0x80 ABI: eax=4 (write), ebx=fd, ecx=buf, edx=len }
    EmitB($B8); EmitI32(4);
    EmitB($BB); EmitI32(STDOUT);
    EmitB($B9); EmitDataRef(dataOff);
    EmitB($BA); EmitI32(len);
    EmitB($CD); EmitB($80);
    Exit;
  end;
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT);
  EmitB($48); EmitB($BE); EmitDataRef(dataOff);
  MovRdxImm(len); EmitSyscall;
end;

procedure EmitMmapArena;
{ Emit an anonymous mmap. Caller sets rsi = length; on return rax = base
  address. Clobbers rax, rcx, r11, rdi, rdx, r10, r8, r9 (mmap syscall ABI);
  rsi is preserved by the kernel. }
begin
  MovRdiImm(0);                          { addr = NULL }
  MovRdxImm(3);                          { PROT_READ | PROT_WRITE }
  EmitB($49); EmitB($BA); EmitI64($22);  { mov r10, MAP_PRIVATE|MAP_ANONYMOUS }
  EmitB($49); EmitB($B8); EmitI64(-1);   { mov r8, -1  (fd) }
  EmitB($49); EmitB($B9); EmitI64(0);    { mov r9, 0   (offset) }
  MovRaxImm(SYS_MMAP);
  EmitSyscall;
end;

procedure EmitExit(code: Int64);
{ exit_group, not exit: terminate every thread. A bare exit (60) only ends
  the calling thread, so a program that started worker threads (e.g. via
  gtk_init / GLib) would leave the process alive after main returns. For a
  single-threaded program the two are equivalent. }
begin
  if TargetArch = TARGET_I386 then
  begin
    { i386 int 0x80 ABI: eax=252 (exit_group), ebx=code }
    EmitB($B8); EmitI32(252);
    EmitB($BB); EmitI32(code);
    EmitB($CD); EmitB($80);
    Exit;
  end;
  MovRaxImm(SYS_EXIT_GROUP); MovRdiImm(code); EmitSyscall;
end;

{ ===== String table ===== }

function InternStr(const s: AnsiString): Integer;
var i, j: Integer; len: Int64; match: Boolean;
begin
  for i := 0 to StrCount-1 do
  begin
    if Strs[i].Len = Length(s) then
    begin
      match := True;
      for j := 1 to Length(s) do
        if Strs[i].Text[j] <> s[j] then match := False;
      if match then begin Result := i; Exit; end;
    end;
  end;
  if StrCount >= MAX_STRS then Error('string table overflow');
  Strs[StrCount].Text   := s;
  Strs[StrCount].Offset := DataLen;
  Strs[StrCount].Len    := Length(s);
  
  { Write 8-byte length prefix }
  len := Length(s);
  for j := 0 to 7 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := Byte((len shr (j * 8)) and $FF);
    Inc(DataLen);
  end;
  
  for j := 1 to Length(s) do
    begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := Ord(s[j]); Inc(DataLen); end;

  { Explicit NUL terminator after the chars so the char data at Offset+8 is a
    valid C string for PChar()/const char* interop. The alignment padding below
    used to supply this only incidentally (and not at all when the char count
    was already 8-aligned). }
  if DataLen >= MAX_DATA then Error('data overflow');
  Data[DataLen] := 0;
  Inc(DataLen);

  { Align to 8 bytes }
  while (DataLen mod 8) <> 0 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  
  Result := StrCount; Inc(StrCount);
end;

