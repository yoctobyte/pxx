{ SPDX-License-Identifier: Zlib }
unit mimic_socket;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `socket`, the IPv4 TCP subset, over this RTL's PAL socket layer
  (lib/rtl/platform.pas). The same unit serves a desktop program (the POSIX
  backend) and an ESP one (the lwIP backend), which is the point: a NilPy HTTP
  server written against CPython's names runs on both.

  `import socket` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, as mimic_urllib_request does; `--no-shims` turns it into an error.

  WHAT WORKS: socket(AF_INET, SOCK_STREAM); bind((host, port)), listen,
  accept -> (conn, (ip, port)), connect((host, port)), recv, send, sendall,
  close, setsockopt(SOL_SOCKET, SO_REUSEADDR, 1), setblocking, getsockname,
  fileno, and `with`. A host is a dotted quad, '' / '0.0.0.0' (any) or
  'localhost'. settimeout / gettimeout in all three of CPython's modes: None
  blocks, 0 is non-blocking, and t > 0 makes connect, accept, recv and send
  each give up after t seconds with TimeoutError('timed out') -- done as
  CPython does it, a non-blocking socket plus a poll per call.

  UDP: socket(AF_INET, SOCK_DGRAM) with sendto, recvfrom -> (data, (ip,
  port)), and recv; settimeout works on it as on TCP. getaddrinfo(host, port)
  returns MicroPython's single entry. A host NAME resolves through dns.pas
  (lwIP's resolver on an ESP) and an unknown one raises gaierror; MicroPython's
  umqtt and ntptime asked for both (tools/mpy_driver_census.sh net).
  WHAT IT REFUSES, loudly: any family but AF_INET and any type but
  SOCK_STREAM / SOCK_DGRAM (OSError at construction, not a socket that quietly
  is TCP).

  ERRORS are raised as CPython raises them: the OSError SUBCLASS its errno
  selects (ConnectionRefusedError, ConnectionResetError, TimeoutError,
  BlockingIOError, ...) with the text CPython-on-Linux prints --
  `[Errno 111] Connection refused`. The PAL hands back -errno in Linux
  numbering on every backend (the ESP one translates lwIP's newlib errno), so
  the number means the same thing on a desktop and on an ESP32.
  `socket.error` is OSError, as in CPython 3.

  The constants are CPython-on-Linux's values, because they are what a
  program prints; they are mapped to the PAL's own at each call, never passed
  through, so the ESP backend's lwIP numbering is never exposed. }

interface

uses pylib, sysutils, platform, dns, dns_wire_core;   { TDnsIpv4Array }

const
  AF_INET      = 2;
  SOCK_STREAM  = 1;
  SOCK_DGRAM   = 2;
  IPPROTO_TCP  = 6;
  IPPROTO_UDP  = 17;
  SOL_SOCKET   = 1;
  SO_REUSEADDR = 2;
  SHUT_RD      = 0;
  SHUT_WR      = 1;
  SHUT_RDWR    = 2;

type
  BlockingIOError = class(OSError) end;
  error = OSError;
  gaierror = class(OSError) end;

  socket = class
  private
    FHandle: Integer;
    FTimeoutMs: Integer;   { -1 blocking (None), 0 non-blocking, else the timeout }
    FType: Integer;        { SOCK_STREAM or SOCK_DGRAM }
    procedure Wait(events: Integer);
    function RecvFull(p: PByte; want: Integer): Integer;
  public
    constructor Create(family: Integer = AF_INET; type_: Integer = SOCK_STREAM;
      proto: Integer = 0);
    procedure bind(const address: TPyList);
    procedure listen(backlog: Integer = 5);
    function accept: TPyList;
    procedure connect(const address: TPyList);
    function recv(bufsize: Integer): TPyBytes;
    function send(data: TPyBytes): Integer;
    procedure sendall(data: TPyBytes);
    function sendto(data: TPyBytes; const address: TPyList): Integer;
    function recvfrom(bufsize: Integer): TPyList;
    { MicroPython's stream methods, which its socket carries and CPython's does
      not (py/stream.c, v1.26.1). read(n) loops until n bytes or EOF, as
      mp_stream_rw does; read() reads to EOF; readinto fills the buffer or up to
      nbytes; readline keeps the newline; write(buf[, max_len]) and
      write(buf, off, max_len) write everything they are given and return the
      count. umqtt is written against these. }
    function read(n: Integer = -1): TPyBytes;
    function readinto(buf: TPyBytes; nbytes: Integer = -1): Integer;
    function readline(size: Integer = -1): TPyBytes;
    function write(const data: Variant; a2: Integer = -1; a3: Integer = -1): Integer;
    procedure setsockopt(level, optname, value: Integer);
    procedure setblocking(flag: Boolean);
    procedure settimeout(const value: Variant);
    function gettimeout: Variant;
    function getsockname: TPyList;
    procedure shutdown(how: Integer);
    procedure close;
    function fileno: Integer;
    function __enter__: socket;
    procedure __exit__(const a, b, c: Variant);
  end;

{ getaddrinfo(host, port) -> [(family, type, proto, canonname, (ip, port))].
  ONE entry, as MicroPython returns, and every MicroPython caller reads
  [0][-1]; CPython lists one per socket type when `type_` is 0. A dotted quad,
  '' and 'localhost' need no lookup; any other name goes through dns.pas
  (lwIP's resolver on an ESP, whose nameservers come by DHCP). A name that
  does not resolve raises gaierror, an OSError, as CPython does. }
function getaddrinfo(const host: AnsiString; port: Integer; family: Integer = 0;
  type_: Integer = 0; proto: Integer = 0; flags: Integer = 0): TPyList;

implementation

{ PAL error codes are negative errnos in the Linux numbering on every backend. }
{ glibc's strerror text, which is what CPython on Linux prints, for the
  errnos a socket call can produce; anything else prints its number only. }
function SockStrError(e: Integer): AnsiString;
begin
  case e of
    1: SockStrError := 'Operation not permitted';
    4: SockStrError := 'Interrupted system call';
    5: SockStrError := 'Input/output error';
    9: SockStrError := 'Bad file descriptor';
    11: SockStrError := 'Resource temporarily unavailable';
    12: SockStrError := 'Cannot allocate memory';
    13: SockStrError := 'Permission denied';
    22: SockStrError := 'Invalid argument';
    23: SockStrError := 'Too many open files in system';
    24: SockStrError := 'Too many open files';
    32: SockStrError := 'Broken pipe';
    88: SockStrError := 'Socket operation on non-socket';
    89: SockStrError := 'Destination address required';
    90: SockStrError := 'Message too long';
    91: SockStrError := 'Protocol wrong type for socket';
    92: SockStrError := 'Protocol not available';
    93: SockStrError := 'Protocol not supported';
    95: SockStrError := 'Operation not supported';
    97: SockStrError := 'Address family not supported by protocol';
    98: SockStrError := 'Address already in use';
    99: SockStrError := 'Cannot assign requested address';
    100: SockStrError := 'Network is down';
    101: SockStrError := 'Network is unreachable';
    102: SockStrError := 'Network dropped connection on reset';
    103: SockStrError := 'Software caused connection abort';
    104: SockStrError := 'Connection reset by peer';
    105: SockStrError := 'No buffer space available';
    106: SockStrError := 'Transport endpoint is already connected';
    107: SockStrError := 'Transport endpoint is not connected';
    108: SockStrError := 'Cannot send after transport endpoint shutdown';
    110: SockStrError := 'Connection timed out';
    111: SockStrError := 'Connection refused';
    112: SockStrError := 'Host is down';
    113: SockStrError := 'No route to host';
    114: SockStrError := 'Operation already in progress';
    115: SockStrError := 'Operation now in progress';
  else
    SockStrError := 'Unknown error ' + IntToStr(e);
  end;
end;

{ Raise what CPython raises for -errno `rc`: the PEP 3151 subclass the errno
  selects, str() `[Errno N] <strerror>`. `what` names the call only when the
  backend reported no errno at all (a bare -1 with nothing behind it). }
procedure Fail(const what: AnsiString; rc: Int64);
var e: Integer; msg: AnsiString;
begin
  e := -rc;
  if e <= 0 then raise OSError.Create(what + ' failed (no errno)');
  msg := '[Errno ' + IntToStr(e) + '] ' + SockStrError(e);
  case e of
    11, 114, 115: raise BlockingIOError.Create(msg);   { EAGAIN EALREADY EINPROGRESS }
    32, 108: raise BrokenPipeError.Create(msg);         { EPIPE ESHUTDOWN }
    103: raise ConnectionAbortedError.Create(msg);
    104: raise ConnectionResetError.Create(msg);
    111: raise ConnectionRefusedError.Create(msg);
    110: raise TimeoutError.Create(msg);
    4: raise InterruptedError.Create(msg);
  end;
  raise OSError.Create(msg);
end;

function IpText(a: LongWord): AnsiString;
begin
  IpText := IntToStr((a shr 24) and 255) + '.' + IntToStr((a shr 16) and 255) + '.' +
            IntToStr((a shr 8) and 255) + '.' + IntToStr(a and 255);
end;

{ '' / '0.0.0.0' / 'localhost' / a dotted quad -> host-order address. }
function HostAddr(const host: AnsiString): LongWord;
var i, part, dots: Integer; acc: LongWord; ok: Boolean;
begin
  if (host = '') or (host = '0.0.0.0') then begin HostAddr := PAL_NET_IP_ANY; Exit; end;
  if host = 'localhost' then begin HostAddr := PAL_NET_IP_LOOPBACK; Exit; end;
  acc := 0; part := -1; dots := 0; ok := True;
  for i := 1 to Length(host) do
    if (host[i] >= '0') and (host[i] <= '9') then
    begin
      if part < 0 then part := 0;
      part := part * 10 + Ord(host[i]) - Ord('0');
      if part > 255 then ok := False;
    end
    else if (host[i] = '.') and (part >= 0) then
    begin
      acc := (acc shl 8) or LongWord(part);
      part := -1;
      dots := dots + 1;
    end
    else
      ok := False;
  if (not ok) or (dots <> 3) or (part < 0) then
    raise gaierror.Create('[Errno -2] Name or service not known');
  HostAddr := (acc shl 8) or LongWord(part);
end;

{ HostAddr, or a dns.pas lookup when the host is a name. }
function ResolveAddr(const host: AnsiString): LongWord;
var ips: TDnsIpv4Array; count, rc, i: Integer; numeric: Boolean;
begin
  numeric := (host = '') or (host = 'localhost');
  if not numeric then
  begin
    numeric := True;
    for i := 1 to Length(host) do
      if not (((host[i] >= '0') and (host[i] <= '9')) or (host[i] = '.')) then
        numeric := False;
  end;
  if numeric then begin ResolveAddr := HostAddr(host); Exit; end;
  count := 0;
  rc := DnsResolveHost(host, ips, count);
  if (rc < 0) or (count < 1) then
    raise gaierror.Create('[Errno -2] Name or service not known');
  ResolveAddr := ips[0];
end;

procedure SplitAddress(const address: TPyList; var addr: LongWord; var port: Integer);
var h: AnsiString;
begin
  if address.count <> 2 then
    raise OSError.Create('socket: an AF_INET address is a (host, port) pair');
  h := address.at(0);
  port := address.at(1);
  addr := ResolveAddr(h);
end;

function AddrPair(addr: LongWord; port: Integer): TPyList;
var l: TPyList; v: Variant;
begin
  l := TPyList.Create;
  v := IpText(addr);
  l.append(v);
  v := port;
  l.append(v);
  AddrPair := pylist_mark_tuple(l);   { tuple(l) would COPY and strand l }
end;

constructor socket.Create(family: Integer; type_: Integer; proto: Integer);
begin
  if family <> AF_INET then
    raise OSError.Create('socket: only AF_INET is supported');
  if (type_ <> SOCK_STREAM) and (type_ <> SOCK_DGRAM) then
    raise OSError.Create('socket: only SOCK_STREAM and SOCK_DGRAM are supported');
  FTimeoutMs := -1;
  FType := type_;
  if type_ = SOCK_DGRAM then
    FHandle := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0)
  else
    FHandle := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if FHandle < 0 then Fail('socket', FHandle);
end;

procedure socket.bind(const address: TPyList);
var addr: LongWord; port, rc: Integer;
begin
  SplitAddress(address, addr, port);
  rc := PalBindIpv4(FHandle, addr, port);
  if rc < 0 then Fail('bind', rc);
end;

procedure socket.listen(backlog: Integer);
var rc: Integer;
begin
  rc := PalListen(FHandle, backlog);
  if rc < 0 then Fail('listen', rc);
end;

{ Timeout mode only: block up to the timeout for `events`, else raise
  TimeoutError('timed out'), CPython's own words (socket.timeout is it). }
procedure socket.Wait(events: Integer);
var rc: Integer;
begin
  if FTimeoutMs <= 0 then Exit;
  rc := PalPoll(FHandle, events, FTimeoutMs);
  if rc < 0 then Fail('poll', rc);
  if rc = 0 then raise TimeoutError.Create('timed out');
end;

function socket.accept: TPyList;
var h, port: Integer; addr: LongWord; conn: socket; l: TPyList;
begin
  addr := 0; port := 0;
  Wait(PAL_POLL_IN);
  h := PalAcceptIpv4(FHandle, addr, port);
  if h < 0 then Fail('accept', h);
  conn := socket.Create;
  PalSocketClose(conn.FHandle);   { the fresh one Create made; take the accepted one }
  conn.FHandle := h;
  l := TPyList.Create;
  l.append(TObject(conn));
  PXXObjRelease(Pointer(conn));   { the list holds it now }
  l.append(TObject(AddrPair(addr, port)));
  accept := pylist_mark_tuple(l);
end;

procedure socket.connect(const address: TPyList);
var addr: LongWord; port, rc: Integer;
begin
  SplitAddress(address, addr, port);
  rc := PalConnectIpv4(FHandle, addr, port);
  if (rc = PAL_NET_EINPROGRESS) and (FTimeoutMs > 0) then
  begin
    { the socket is non-blocking underneath: wait for the handshake, then
      ask it how it went }
    Wait(PAL_POLL_OUT);
    rc := PalGetSockError(FHandle);
    { a handshake answered by RST was REFUSED; lwIP's SO_ERROR says reset
      (the ESP backend's connect has the same note), Linux says refused }
    if rc = PAL_NET_ECONNRESET then rc := PAL_NET_ECONNREFUSED;
  end;
  if rc < 0 then Fail('connect', rc);
end;

function socket.recv(bufsize: Integer): TPyBytes;
var r: TPyBytes; got: Int64;
begin
  if bufsize < 0 then raise OSError.Create('recv: negative buffersize');
  r := TPyBytes.Create(bufsize);
  got := 0;
  if bufsize > 0 then Wait(PAL_POLL_IN);
  if bufsize > 0 then got := PalRecv(FHandle, r.FData, bufsize);
  if got < 0 then Fail('recv', got);
  r.FLen := got;
  recv := r;
end;

function socket.send(data: TPyBytes): Integer;
var sent: Int64;
begin
  if data.FLen = 0 then begin send := 0; Exit; end;
  Wait(PAL_POLL_OUT);
  sent := PalSend(FHandle, data.FData, data.FLen);
  if sent < 0 then Fail('send', sent);
  send := sent;
end;

procedure socket.sendall(data: TPyBytes);
var done, sent: Int64;
begin
  done := 0;
  while done < data.FLen do
  begin
    Wait(PAL_POLL_OUT);
    sent := PalSend(FHandle, PByte(data.FData) + done, data.FLen - done);
    if sent < 0 then Fail('sendall', sent);
    done := done + sent;
  end;
end;

function socket.sendto(data: TPyBytes; const address: TPyList): Integer;
var addr: LongWord; port: Integer; sent: Int64;
begin
  SplitAddress(address, addr, port);
  Wait(PAL_POLL_OUT);
  sent := PalSendToIpv4(FHandle, data.FData, data.FLen, addr, port);
  if sent < 0 then Fail('sendto', sent);
  sendto := sent;
end;

function socket.recvfrom(bufsize: Integer): TPyList;
var r: TPyBytes; got: Int64; addr: LongWord; port: Integer; l: TPyList;
begin
  if bufsize < 0 then raise OSError.Create('recvfrom: negative buffersize');
  r := TPyBytes.Create(bufsize);
  addr := 0; port := 0;
  Wait(PAL_POLL_IN);
  got := PalRecvFromIpv4(FHandle, r.FData, bufsize, addr, port);
  if got < 0 then Fail('recvfrom', got);
  r.FLen := got;
  l := TPyList.Create;
  l.append(TObject(r));
  PXXObjRelease(Pointer(r));   { the list holds it now }
  l.append(TObject(AddrPair(addr, port)));
  recvfrom := pylist_mark_tuple(l);
end;

{ Recv into p until want bytes or EOF; the count actually read. }
function socket.RecvFull(p: PByte; want: Integer): Integer;
var done: Integer; got: Int64;
begin
  done := 0;
  while done < want do
  begin
    Wait(PAL_POLL_IN);
    got := PalRecv(FHandle, p + done, want - done);
    if got < 0 then Fail('read', got);
    if got = 0 then Break;
    done := done + got;
  end;
  RecvFull := done;
end;

function socket.read(n: Integer): TPyBytes;
var r, buf: TPyBytes; chunk, got: Integer;
begin
  if n >= 0 then
  begin
    r := TPyBytes.Create(n);
    r.FLen := RecvFull(PByte(r.FData), n);
    read := r;
    Exit;
  end;
  { read(): to EOF, a chunk at a time, as stream_readall does }
  r := TPyBytes.Create(0);
  chunk := 256;
  buf := TPyBytes.Create(chunk);
  repeat
    got := RecvFull(PByte(buf.FData), chunk);
    buf.FLen := got;
    r.extend(buf);
    buf.FLen := chunk;
  until got < chunk;
  PXXObjRelease(Pointer(buf));
  read := r;
end;

function socket.readinto(buf: TPyBytes; nbytes: Integer): Integer;
begin
  if (nbytes < 0) or (nbytes > buf.FLen) then nbytes := buf.FLen;
  readinto := RecvFull(PByte(buf.FData), nbytes);
end;

function socket.readline(size: Integer): TPyBytes;
var r: TPyBytes; c: Byte;
begin
  r := TPyBytes.Create(0);
  while (size < 0) or (r.FLen < size) do
  begin
    if RecvFull(@c, 1) = 0 then Break;
    r.append(c);
    if c = 10 then Break;
  end;
  readline := r;
end;

function socket.write(const data: Variant; a2: Integer; a3: Integer): Integer;
var off, len, total, done: Integer; sent: Int64; o: TObject; p: PByte; text: AnsiString;
begin
  { a bytes-like object, or a str, whose UTF-8 bytes MicroPython writes }
  o := nil;
  if pyvar_is_objtag(data) then o := TObject(pyvarobj(data));
  if (o <> nil) and (o is TPyBytes) then
  begin
    p := PByte(TPyBytes(o).FData);
    total := TPyBytes(o).FLen;
  end
  else
  begin
    text := pystr_of(data);
    p := PByte(PAnsiChar(text));
    total := Length(text);
  end;
  off := 0; len := total;
  if a3 >= 0 then begin off := a2; len := a3; end
  else if a2 >= 0 then len := a2;
  if off > total then off := total;
  if len > total - off then len := total - off;
  done := 0;
  while done < len do
  begin
    Wait(PAL_POLL_OUT);
    sent := PalSend(FHandle, p + off + done, len - done);
    if sent < 0 then Fail('write', sent);
    done := done + sent;
  end;
  write := done;
end;

procedure socket.setsockopt(level, optname, value: Integer);
var rc: Integer;
begin
  if (level = SOL_SOCKET) and (optname = SO_REUSEADDR) then
  begin
    rc := PalSetSocketReuseAddr(FHandle, value);
    if rc < 0 then Fail('setsockopt', rc);
  end
  else
    raise OSError.Create('setsockopt: only (SOL_SOCKET, SO_REUSEADDR) is supported');
end;

procedure socket.setblocking(flag: Boolean);
begin
  if flag then settimeout(pynone) else settimeout(0);
end;

procedure socket.settimeout(const value: Variant);
var f: Double; rc, ms: Integer;
begin
  if pystr_of(value) = 'None' then ms := -1
  else
  begin
    f := value;
    if f < 0 then raise ValueError.Create('Timeout value out of range');
    ms := Round(f * 1000);
    if (ms = 0) and (f > 0) then ms := 1;   { a positive timeout never means non-blocking }
  end;
  { None is a blocking socket; 0 and a timeout are non-blocking underneath }
  if ms < 0 then rc := PalSetSocketNonBlocking(FHandle, 0)
  else rc := PalSetSocketNonBlocking(FHandle, 1);
  if rc < 0 then Fail('settimeout', rc);
  FTimeoutMs := ms;
end;

function socket.gettimeout: Variant;
begin
  if FTimeoutMs < 0 then gettimeout := pynone
  else gettimeout := FTimeoutMs / 1000.0;
end;

function socket.getsockname: TPyList;
var addr: LongWord; port, rc: Integer;
begin
  addr := 0; port := 0;
  rc := PalGetSockNameIpv4(FHandle, addr, port);
  if rc < 0 then Fail('getsockname', rc);
  getsockname := AddrPair(addr, port);
end;

procedure socket.shutdown(how: Integer);
var rc: Integer;
begin
  rc := PalShutdown(FHandle, how);
  if rc < 0 then Fail('shutdown', rc);
end;

procedure socket.close;
begin
  if FHandle >= 0 then PalSocketClose(FHandle);
  FHandle := -1;
end;

function socket.fileno: Integer;
begin
  fileno := FHandle;
end;

function socket.__enter__: socket;
begin
  __enter__ := Self;
end;

procedure socket.__exit__(const a, b, c: Variant);
begin
  close;
end;

function getaddrinfo(const host: AnsiString; port: Integer; family: Integer;
  type_: Integer; proto: Integer; flags: Integer): TPyList;
var e, l: TPyList; v: Variant;
begin
  if (family <> 0) and (family <> AF_INET) then
    raise gaierror.Create('[Errno -9] Address family for hostname not supported');
  if type_ = 0 then type_ := SOCK_STREAM;
  if proto = 0 then
    if type_ = SOCK_DGRAM then proto := IPPROTO_UDP else proto := IPPROTO_TCP;
  e := TPyList.Create;
  v := AF_INET; e.append(v);
  v := type_; e.append(v);
  v := proto; e.append(v);
  v := ''; e.append(v);
  e.append(TObject(AddrPair(ResolveAddr(host), port)));
  l := TPyList.Create;
  l.append(TObject(pylist_mark_tuple(e)));
  getaddrinfo := l;
end;

end.
