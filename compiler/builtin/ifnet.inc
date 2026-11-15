{ ifnet.inc -- network interfaces for the BSD translators, the Linux way.
  Included after proctext.inc (TxPtr and the Tx text helpers). The host
  unit defines, before the include:

    IFN_REQ          its struct ifreq size (32; NetBSD 144)
    IFN_FIXED_STEP   True when SIOCGIFCONF entries are IFN_REQ apart
                     (NetBSD) rather than 16 + max(sa_len, 16) (the rest)
    IFN_GIFCONF, IFN_GIFFLAGS, IFN_GIFADDR, IFN_GIFNETMASK, IFN_GIFBRDADDR
                     its ioctl numbers
    function IfnIoctl(fd, req: Int64; arg: TxPtr): Int64;
                     the kernel's ioctl, answering >= 0 or a -Linux errno
    function IfnTmpSock: Int64;  procedure IfnCloseFd(fd: Int64);
                     an AF_INET datagram socket to carry SIOCGIFCONF
    function IfnHostIndex(name: TxPtr): Int64;
    function IfnHostName(idx: Int64; dst: TxPtr): Boolean;
                     a name's interface index and back when the system can
                     say (OpenBSD, through libc); -1 / False to use the
                     AF_LINK entries of SIOCGIFCONF, which carry sdl_index

  What it gives: IfnProcNetDev (the text of /proc/net/dev, for crtl's
  if_nameindex) and IfnLinuxIoctl (SIOCGIFCONF, SIOCGIFFLAGS, SIOCGIFADDR,
  SIOCGIFNETMASK, SIOCGIFBRDADDR, SIOCGIFINDEX, SIOCGIFNAME in their Linux
  layouts, for crtl's getifaddrs and if_nametoindex). One scratch buffer, so
  two threads asking at once can mix their answers; the readers are one-shot.

  /proc/net/dev's counters are all 0: the names are what is read. }

const
  IFN_NOT_MINE = -$7FFFFFFF;           { not an interface ioctl: the caller's own case }
  IfnHdr1: array[0..75] of Byte = (73,110,116,101,114,45,124,32,32,32,82,101,99,101,105,118,101,32,32,32,32,32,32,
    32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,
    32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,124,32,32,84,114,97,110,115,109,
    105,116);
    { Linux's first header line }
  IfnHdr2: array[0..121] of Byte = (32,102,97,99,101,32,124,98,121,116,101,115,32,32,32,32,112,97,99,107,101,116,
    115,32,101,114,114,115,32,100,114,111,112,32,102,105,102,111,32,102,114,97,109,
    101,32,99,111,109,112,114,101,115,115,101,100,32,109,117,108,116,105,99,97,115,
    116,124,98,121,116,101,115,32,32,32,32,112,97,99,107,101,116,115,32,101,114,114,
    115,32,100,114,111,112,32,102,105,102,111,32,99,111,108,108,115,32,99,97,114,
    114,105,101,114,32,99,111,109,112,114,101,115,115,101,100);
    { and its second }
  ProcNetDev: array[0..12] of Byte = (47,112,114,111,99,47,110,101,116,47,100,101,118);   { /proc/net/dev }

var
  IfnBuf: array[0..32767] of Byte;
  IfnLen: Int64;

function ProcIsNetDev(p: TxPtr): Boolean;
begin
  Result := TxPathIs(p, @ProcNetDev[0], Length(ProcNetDev));
end;

{ Fill IfnBuf with the kernel's SIOCGIFCONF list; IfnLen is its length,
  or -1. }
procedure IfnScan;
var fd: Int64; ifc: array[0..1] of Int64; r: Int64;
begin
  IfnLen := -1;
  fd := IfnTmpSock;
  if fd < 0 then Exit;
  ifc[0] := Length(IfnBuf);               { int ifc_len, then the buffer pointer at 8 }
  ifc[1] := TxPtr(@IfnBuf[0]);
  r := IfnIoctl(fd, IFN_GIFCONF, TxPtr(@ifc[0]));
  IfnCloseFd(fd);
  if r < 0 then Exit;
  IfnLen := ifc[0] and $7FFFFFFF;
end;

{ The entry after the one at offset o. }
function IfnNext(o: Int64): Int64;
var l: Int64;
begin
  if IFN_FIXED_STEP then Result := o + IFN_REQ
  else
  begin
    l := IfnBuf[o + 16];
    if l < 16 then l := 16;
    Result := o + 16 + l;
  end;
end;

{ Do the 16-byte names at a and b match (NUL-terminated within 16)? }
function IfnNameEq(a, b: TxPtr): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to 15 do
  begin
    if PByte(a + i)^ <> PByte(b + i)^ then Exit;
    if PByte(a + i)^ = 0 then Break;
  end;
  Result := True;
end;

{ Has the name of the entry at o appeared in an earlier entry? }
function IfnSeenBefore(o: Int64): Boolean;
var q: Int64;
begin
  Result := False;
  q := 0;
  while q < o do
  begin
    if IfnNameEq(TxPtr(@IfnBuf[q]), TxPtr(@IfnBuf[o])) then begin Result := True; Exit; end;
    q := IfnNext(q);
  end;
end;

procedure IfnProcNetDev(b: TxPtr; var n: TxPtr; cap: Int64);
var o, k, i: Int64;
begin
  TxLit(b, n, @IfnHdr1[0], Length(IfnHdr1)); TxPut(b, n, 10);
  TxLit(b, n, @IfnHdr2[0], Length(IfnHdr2)); TxPut(b, n, 10);
  IfnScan;
  if IfnLen < 0 then Exit;
  o := 0;
  while (o + 16 <= IfnLen) and (n + 120 < cap) do
  begin
    if (IfnBuf[o] <> 0) and not IfnSeenBefore(o) then
    begin
      k := 0;
      while (k < 16) and (IfnBuf[o + k] <> 0) do k := k + 1;
      for i := k to 5 do TxPut(b, n, 32);           { Linux right-aligns the name in 6 }
      TxStr(b, n, TxPtr(@IfnBuf[o]), 16, False);
      TxPut(b, n, 58);
      for i := 1 to 16 do begin TxPut(b, n, 32); TxPut(b, n, 48); end;
      TxPut(b, n, 10);
    end;
    o := IfnNext(o);
  end;
end;

{ The interface index of the 16-byte name at nm, or -1. }
function IfnIndexOf(nm: TxPtr): Int64;
var o: Int64;
begin
  Result := IfnHostIndex(nm);
  if Result >= 0 then Exit;
  Result := -1;
  IfnScan;
  o := 0;
  while o + 16 <= IfnLen do
  begin
    if (IfnBuf[o + 17] = 18) and IfnNameEq(TxPtr(@IfnBuf[o]), nm) then   { AF_LINK }
    begin
      Result := IfnBuf[o + 18] or (Int64(IfnBuf[o + 19]) shl 8);       { sdl_index }
      Exit;
    end;
    o := IfnNext(o);
  end;
end;

{ The name of interface idx into the 16 bytes at dst. }
function IfnNameOf(idx: Int64; dst: TxPtr): Boolean;
var o: Int64; i: Integer;
begin
  Result := IfnHostName(idx, dst);
  if Result then Exit;
  IfnScan;
  o := 0;
  while o + 16 <= IfnLen do
  begin
    if (IfnBuf[o + 17] = 18) and ((IfnBuf[o + 18] or (Int64(IfnBuf[o + 19]) shl 8)) = idx) then
    begin
      for i := 0 to 15 do PByte(dst + i)^ := IfnBuf[o + i];
      Result := True;
      Exit;
    end;
    o := IfnNext(o);
  end;
end;

{ A BSD sockaddr_in (len, family, port, addr) at s as Linux's (family as
  16 bits, port, addr, 8 zero bytes) at d. }
procedure IfnSinToLinux(s, d: TxPtr);
var i: Integer;
begin
  for i := 0 to 15 do PByte(d + i)^ := 0;
  PWord(d)^ := PByte(s + 1)^;
  for i := 2 to 7 do PByte(d + i)^ := PByte(s + i)^;
end;

{ Linux ioctl `req` on fd with its argument at arg, or IFN_NOT_MINE. A Linux
  ifreq is 40 bytes: the name, then the union at 16. }
function IfnLinuxIoctl(fd, req: Int64; arg: TxPtr): Int64;
var r: array[0..18] of Int64; rq, o, k, cap, outp, idx: Int64; i: Integer; f: Int64;
begin
  Result := IFN_NOT_MINE;
  case req of
    $8912:                                            { SIOCGIFCONF: the AF_INET addresses }
      begin
        IfnScan;
        if IfnLen < 0 then begin Result := -19; Exit; end;      { ENODEV }
        cap := PInteger(arg)^;
        outp := PInt64(arg + 8)^;
        k := 0; o := 0;
        while o + 16 <= IfnLen do
        begin
          if IfnBuf[o + 17] = 2 then
          begin
            if outp <> 0 then
            begin
              if k + 40 > cap then Break;
              for i := 0 to 39 do PByte(outp + k + i)^ := 0;
              for i := 0 to 15 do PByte(outp + k + i)^ := IfnBuf[o + i];
              IfnSinToLinux(TxPtr(@IfnBuf[o + 16]), outp + k + 16);
            end;
            k := k + 40;
          end;
          o := IfnNext(o);
        end;
        PInteger(arg)^ := k;
        Result := 0;
      end;
    $8913, $8915, $8919, $891B:                       { FLAGS, ADDR, BRDADDR, NETMASK }
      begin
        for i := 0 to 18 do r[i] := 0;
        for i := 0 to 15 do PByte(TxPtr(@r[0]) + i)^ := PByte(arg + i)^;
        if req = $8913 then rq := IFN_GIFFLAGS
        else if req = $8915 then rq := IFN_GIFADDR
        else if req = $8919 then rq := IFN_GIFBRDADDR
        else rq := IFN_GIFNETMASK;
        Result := IfnIoctl(fd, rq, TxPtr(@r[0]));
        if Result < 0 then Exit;
        for i := 16 to 39 do PByte(arg + i)^ := 0;
        if req = $8913 then
        begin
          { the bits both agree on, and IFF_MULTICAST ($8000 on the BSDs, $1000 here) }
          f := PWord(TxPtr(@r[0]) + 16)^;
          i := f and $3FF;
          if (f and $8000) <> 0 then i := i or $1000;
          PWord(arg + 16)^ := i;
        end
        else
        begin
          IfnSinToLinux(TxPtr(@r[0]) + 16, arg + 16);
          PWord(arg + 16)^ := 2;    { a BSD netmask often says family 0, sa_len 5 }
        end;
        Result := 0;
      end;
    $8933:                                            { SIOCGIFINDEX: ifr_ifindex at 16 }
      begin
        idx := IfnIndexOf(arg);
        if idx < 0 then begin Result := -19; Exit; end;
        PInteger(arg + 16)^ := idx;
        Result := 0;
      end;
    $8910:                                            { SIOCGIFNAME: index at 16 in, name out }
      begin
        if IfnNameOf(PInteger(arg + 16)^, arg) then Result := 0 else Result := -19;
      end;
  end;
end;
