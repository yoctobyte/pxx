{ Text for the /proc files a translated --os builds itself (fbsdabi, nbsdabi,
  obsdabi, dfbsdabi, minixabi). Included in the implementation part of each;
  the unit declares `type TxPtr = Int64;` (LongInt on i386) first, and keeps
  its own PathIs (this file uses TxPathIs). Bytes and pointers only, no managed types, as everywhere in
  these units: they are compiled before the heap exists.

  What the files are for:
  - /proc/self/fdinfo/N: the compiler's output guard (compiler/output_guard.inc)
    compares a file's `mnt_id:` and `ino:` lines. The device number stands in
    for the mount id: one per mounted file system, as mnt_id is on Linux.
  - /proc/mounts and /proc/self/mounts: crtl's getmntent (df, mount listings).
  - /proc/stat: the cpu lines; palparallel samples the idle share.
  Each unit builds the text in a scratch mapping and hands it back as a file
  the way it answers /proc/self/environ. }

procedure TxPut(b: TxPtr; var n: TxPtr; c: Byte);
begin
  PByte(b + n)^ := c;
  n := n + 1;
end;

procedure TxDec(b: TxPtr; var n: TxPtr; v: Int64);
var d: array[0..23] of Byte; k: Integer;
begin
  if v < 0 then begin TxPut(b, n, 45); v := -v; end;
  k := 0;
  repeat
    d[k] := 48 + (v mod 10);
    v := v div 10;
    k := k + 1;
  until v = 0;
  while k > 0 do begin k := k - 1; TxPut(b, n, d[k]); end;
end;

{ A C string of at most cap bytes, with /proc/mounts' octal escapes for space,
  tab, newline and backslash when esc is set. }
procedure TxStr(b: TxPtr; var n: TxPtr; p: TxPtr; cap: Integer; esc: Boolean);
var c: Byte; i: Integer;
begin
  i := 0;
  while (i < cap) and (PByte(p + i)^ <> 0) do
  begin
    c := PByte(p + i)^;
    if esc and ((c = 32) or (c = 9) or (c = 10) or (c = 92)) then
    begin
      TxPut(b, n, 92);
      TxPut(b, n, 48 + (c shr 6));
      TxPut(b, n, 48 + ((c shr 3) and 7));
      TxPut(b, n, 48 + (c and 7));
    end
    else TxPut(b, n, c);
    i := i + 1;
  end;
end;

procedure TxLit(b: TxPtr; var n: TxPtr; w: PByte; len: Integer);
var i: Integer;
begin
  for i := 0 to len - 1 do TxPut(b, n, w[i]);
end;

const
  ProcFdInfoPre: array[0..17] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                         102,100,105,110,102,111,47);         { /proc/self/fdinfo/ }
  ProcMounts: array[0..11] of Byte = (47,112,114,111,99,47,109,111,117,110,116,115);  { /proc/mounts }
  ProcSelfMounts: array[0..16] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                          109,111,117,110,116,115);           { /proc/self/mounts }
  ProcStat: array[0..9] of Byte = (47,112,114,111,99,47,115,116,97,116);    { /proc/stat }
  TxFdInfo1: array[0..23] of Byte = (112,111,115,58,9,48,10,102,108,97,103,115,58,9,48,10,
                                     109,110,116,95,105,100,58,9);           { pos:\t0\nflags:\t0\nmnt_id:\t }
  TxIno: array[0..5] of Byte = (10,105,110,111,58,9);                       { \nino:\t }
  TxNosuid: array[0..6] of Byte = (44,110,111,115,117,105,100);             { ,nosuid }
  TxNoexec: array[0..6] of Byte = (44,110,111,101,120,101,99);              { ,noexec }

{ The N of /proc/self/fdinfo/N, or -1. }
function ProcFdInfoNum(p: TxPtr): TxPtr;
var i: Integer; c: Byte;
begin
  Result := -1;
  if p = 0 then Exit;
  for i := 0 to 17 do
    if PByte(p + i)^ <> ProcFdInfoPre[i] then Exit;
  i := 18;
  c := PByte(p + i)^;
  if (c < 48) or (c > 57) then Exit;
  Result := 0;
  while (c >= 48) and (c <= 57) do
  begin
    Result := Result * 10 + (c - 48);
    i := i + 1;
    c := PByte(p + i)^;
  end;
  if c <> 0 then Result := -1;
end;

{ Does the C string at p equal the n bytes at w? (fbsdabi's PathIs.) }
function TxPathIs(p: TxPtr; w: PByte; n: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if p = 0 then Exit;
  for i := 0 to n - 1 do
    if PByte(p + i)^ <> w[i] then Exit;
  Result := PByte(p + n)^ = 0;
end;

{ Is p one of /proc/mounts, /proc/self/mounts? }
function ProcIsMounts(p: TxPtr): Boolean;
begin
  Result := TxPathIs(p, @ProcMounts[0], Length(ProcMounts))
            or TxPathIs(p, @ProcSelfMounts[0], Length(ProcSelfMounts));
end;

function ProcIsStat(p: TxPtr): Boolean;
begin
  Result := TxPathIs(p, @ProcStat[0], Length(ProcStat));
end;

{ fdinfo's text: Linux's first four lines. }
procedure TxFdInfo(b: TxPtr; var n: TxPtr; dev, ino: Int64);
begin
  TxLit(b, n, @TxFdInfo1[0], Length(TxFdInfo1));
  TxDec(b, n, dev);
  TxLit(b, n, @TxIno[0], Length(TxIno));
  TxDec(b, n, ino);
  TxPut(b, n, 10);
end;

{ One /proc/mounts line: "from on type opts 0 0". The names are C strings of
  at most cap bytes each. }
procedure TxMount(b: TxPtr; var n: TxPtr; mntFrom, mntOn, fstype: TxPtr; cap: Integer;
                  ro, nosuid, noexec: Boolean);
begin
  TxStr(b, n, mntFrom, cap, True);
  TxPut(b, n, 32);
  TxStr(b, n, mntOn, cap, True);
  TxPut(b, n, 32);
  TxStr(b, n, fstype, cap, True);
  TxPut(b, n, 32);
  TxPut(b, n, 114);
  if ro then TxPut(b, n, 111) else TxPut(b, n, 119);                  { ro / rw }
  if nosuid then TxLit(b, n, @TxNosuid[0], Length(TxNosuid));
  if noexec then TxLit(b, n, @TxNoexec[0], Length(TxNoexec));
  TxPut(b, n, 32); TxPut(b, n, 48); TxPut(b, n, 32); TxPut(b, n, 48);
  TxPut(b, n, 10);
end;

{ One /proc/stat cpu line ("cpu " when cpu < 0, else "cpuN"), in Linux's
  order: user nice system idle iowait irq softirq steal guest guest_nice. The
  BSDs count user, nice, system, interrupt and idle (OpenBSD also spin, which
  the caller adds to system); iowait and the rest are 0. }
procedure TxCpuLine(b: TxPtr; var n: TxPtr; cpu: Integer; user, nice, sys, idle, irq: Int64);
var k: Integer;
begin
  TxPut(b, n, 99); TxPut(b, n, 112); TxPut(b, n, 117);              { cpu }
  if cpu < 0 then TxPut(b, n, 32) else TxDec(b, n, cpu);
  TxPut(b, n, 32); TxDec(b, n, user);
  TxPut(b, n, 32); TxDec(b, n, nice);
  TxPut(b, n, 32); TxDec(b, n, sys);
  TxPut(b, n, 32); TxDec(b, n, idle);
  TxPut(b, n, 32); TxPut(b, n, 48);                                 { iowait }
  TxPut(b, n, 32); TxDec(b, n, irq);
  for k := 1 to 4 do begin TxPut(b, n, 32); TxPut(b, n, 48); end;   { softirq steal guest guest_nice }
  TxPut(b, n, 10);
end;
