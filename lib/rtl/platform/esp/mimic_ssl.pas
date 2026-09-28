{ SPDX-License-Identifier: Zlib }
unit mimic_ssl;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's `ssl` module, the TLS client, for a NilPy program on an ESP32.
  `import ssl` resolves here through the mimic_ fallback, and only for an ESP
  build: this file lives in lib/rtl/platform/esp, on the unit path of an
  --platform=esp compile and of nothing else.

      import socket, ssl
      s = socket.socket()
      s.connect(socket.getaddrinfo("example.com", 443)[0][-1])
      s = ssl.wrap_socket(s, server_hostname="example.com")
      s.write(b"GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")
      print(s.read(64))

      ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
      ctx.verify_mode = ssl.CERT_REQUIRED
      ctx.load_verify_locations(cadata=ca_pem_bytes)
      s = ctx.wrap_socket(s, server_hostname="example.com")

  This is what urequests' https:// and umqtt.simple's ssl=True reach, and
  both run unchanged: the returned SSLSocket IS a socket.socket (a subclass
  whose three stream primitives encrypt), so read/readinto/readline/write/
  recv/send/sendall/close behave as they do on a plain socket.

  CERTIFICATE VERIFICATION IS OFF BY DEFAULT, BECAUSE MICROPYTHON'S IS.
  `ssl.wrap_socket(...)` defaults to cert_reqs=CERT_NONE, and
  `ssl.SSLContext(...)` sets verify_mode = CERT_NONE in its constructor
  (micropython-lib python-stdlib/ssl/ssl.py, which is what `import ssl` is on
  the esp32 port). The connection is ENCRYPTED BUT NOT AUTHENTICATED: anyone
  on the path can present any certificate. To authenticate the server, set
  CERT_REQUIRED and load the CA that signs it with
  load_verify_locations(cadata=...) (PEM or DER bytes), and pass
  server_hostname, which is then checked against the certificate; as in
  MicroPython, CERT_REQUIRED without server_hostname is a ValueError. There is
  no built-in CA bundle, again as in MicroPython. A certificate that fails
  verification raises ValueError carrying mbedTLS's reason.

  THE BACKEND is the chip's own mbedTLS (lib/rtl/platform/esp/idf/pxx_tls,
  C, and it says why), the library MicroPython's esp32 port uses: TLS 1.2
  (and 1.3 if the sdkconfig enables it), the chip's AES/SHA/MPI hardware.
  A project needs that component: add lib/rtl/platform/esp/idf to
  EXTRA_COMPONENT_DIRS and pxx_tls to main's REQUIRES. Without it the link
  fails naming pxx_tls_connect, which is the refusal.

  WHAT IS NOT HERE, AND SAYS SO: the server side (server_side=True and
  load_cert_chain raise NotImplementedError), DTLS, getpeercert(), and a
  handshake deferred past wrap_socket (do_handshake=False is accepted and the
  handshake still runs at once, which is only observable as timing). }

interface

uses pylib, sysutils, mimic_socket;

const
  CERT_NONE     = 0;   { MBEDTLS_SSL_VERIFY_NONE / _OPTIONAL / _REQUIRED, }
  CERT_OPTIONAL = 1;   { which are MicroPython's values }
  CERT_REQUIRED = 2;
  PROTOCOL_TLS_CLIENT = 0;
  PROTOCOL_TLS_SERVER = 1;

type
  SSLSocket = class(socket)
  protected
    FTls: Pointer;
    procedure Wait(events: Integer); override;
    function RawRecv(p: PByte; len: Integer): Int64; override;
    function RawSend(p: PByte; len: Integer): Int64; override;
  public
    procedure close; override;
    { the negotiated suite, as mbedTLS names it, e.g.
      TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256 }
    function cipher: AnsiString;
    destructor Destroy; override;
  end;

  SSLContext = class
  private
    FProtocol: Integer;
    FCa: AnsiString;
  public
    verify_mode: Integer;
    constructor Create(protocol: Integer = PROTOCOL_TLS_CLIENT);
    procedure load_verify_locations(const cafile: Variant = 0; const cadata: Variant = 0);
    procedure load_cert_chain(const certfile: Variant = 0; const keyfile: Variant = 0);
    function wrap_socket(sock: socket; server_side: Boolean = False;
      do_handshake_on_connect: Boolean = True;
      const server_hostname: Variant = 0): SSLSocket;
  end;

{ A Variant argument left out arrives as 0 (the unit-wide convention for an
  optional object argument); 0 and None both mean "not given". }
function wrap_socket(sock: socket; server_side: Boolean = False;
  const key: Variant = 0; const cert: Variant = 0; cert_reqs: Integer = CERT_NONE;
  const cadata: Variant = 0; const server_hostname: Variant = 0;
  do_handshake: Boolean = True): SSLSocket;

implementation

uses platform, newliberrno;

const
  PXX_TLS_TIMEOUT = -$6800;   { pxx_tls.c: the socket's timeout ran out }
  X509_BAD_INPUT  = -$2800;   { MBEDTLS_ERR_X509_BAD_INPUT_DATA }
  X509_ANY_LO     = -$3000;   { mbedTLS's X509 module: -0x2080 .. -0x3000 }
  X509_ANY_HI     = -$2080;
  X509_VERIFY_FAILED = -$2700;

function pxx_tls_connect(fd: Integer; host: PAnsiChar; authmode: Integer;
  ca: PByte; calen, timeoutMs: Integer; err: PInteger; msg: PAnsiChar;
  msglen: Integer): Pointer; cdecl; external;
function pxx_tls_read(h: Pointer; buf: PByte; len, timeoutMs: Integer): Integer; cdecl; external;
function pxx_tls_write(h: Pointer; buf: PByte; len, timeoutMs: Integer): Integer; cdecl; external;
function pxx_tls_cipher(h: Pointer): PAnsiChar; cdecl; external;
procedure pxx_tls_close(h: Pointer); cdecl; external;
function pxx_tls_strerror(err: Integer; buf: PAnsiChar; buflen: Integer): Integer; cdecl; external;

{ not given: None, or the 0 an omitted optional argument arrives as }
function IsNone(const v: Variant): Boolean;
var t: AnsiString;
begin
  if pyvar_is_objtag(v) then begin IsNone := False; Exit; end;
  t := pystr_of(v);
  IsNone := (t = 'None') or (t = '0');
end;

{ bytes, bytearray or str -> the raw bytes }
function BytesOf(const v: Variant): AnsiString;
var o: TObject; r: AnsiString;
begin
  o := nil;
  if pyvar_is_objtag(v) then o := TObject(pyvarobj(v));
  if (o <> nil) and (o is TPyBytes) then
  begin
    SetLength(r, TPyBytes(o).FLen);
    if TPyBytes(o).FLen > 0 then Move(PByte(TPyBytes(o).FData)^, r[1], TPyBytes(o).FLen);
    BytesOf := r;
  end
  else
    BytesOf := pystr_of(v);
end;

{ An error code from pxx_tls, raised as MicroPython raises it: a socket errno
  (a small negative) as that errno's OSError, the timeout as TimeoutError, and
  an mbedTLS code as OSError carrying mbedTLS's own text. }
procedure TlsFail(const what: AnsiString; err, timeoutMs: Integer);
var buf: array[0..127] of AnsiChar; n: Integer; text: AnsiString;
begin
  if err = PXX_TLS_TIMEOUT then
  begin
    if timeoutMs = 0 then SocketFail(what, -11);   { EAGAIN, as a plain socket }
    raise TimeoutError.Create('timed out');
  end;
  if (err < 0) and (err > -256) then
    SocketFail(what, -NewlibToLinuxErrno(-err));
  n := pxx_tls_strerror(err, @buf[0], 128);
  SetLength(text, n);
  if n > 0 then Move(buf[0], text[1], n);
  raise OSError.Create('(' + IntToStr(err) + ', ''' + text + ''')');
end;

{ ---- SSLSocket ------------------------------------------------------------ }

procedure SSLSocket.Wait(events: Integer);
begin
  { nothing: pxx_tls waits on the fd itself, with the socket's timeout, and
    must not be pre-empted by a poll that cannot see bytes mbedTLS has
    already decrypted and is holding }
end;

function SSLSocket.RawRecv(p: PByte; len: Integer): Int64;
var n: Integer;
begin
  if FTls = nil then begin RawRecv := -9; Exit; end;   { EBADF: closed }
  if len <= 0 then begin RawRecv := 0; Exit; end;
  n := pxx_tls_read(FTls, p, len, FTimeoutMs);
  if n < 0 then TlsFail('read', n, FTimeoutMs);
  RawRecv := n;
end;

function SSLSocket.RawSend(p: PByte; len: Integer): Int64;
var n: Integer;
begin
  if FTls = nil then begin RawSend := -9; Exit; end;
  if len <= 0 then begin RawSend := 0; Exit; end;
  n := pxx_tls_write(FTls, p, len, FTimeoutMs);
  if n < 0 then TlsFail('write', n, FTimeoutMs);
  RawSend := n;
end;

procedure SSLSocket.close;
begin
  if FTls <> nil then pxx_tls_close(FTls);
  FTls := nil;
  inherited close;
end;

function SSLSocket.cipher: AnsiString;
begin
  if FTls = nil then cipher := '' else cipher := AnsiString(pxx_tls_cipher(FTls));
end;

{ MicroPython closes an unreferenced SSL socket in its finaliser; this is the
  same, and it is what keeps a dropped connection from holding its ~20 KB of
  mbedTLS record buffers for ever. }
destructor SSLSocket.Destroy;
begin
  close;
  inherited Destroy;
end;

{ The handshake: `sock`'s fd moves into the new SSLSocket (sock is left
  closed, as CPython's detach leaves it). }
function Connect(sock: socket; authmode: Integer; const ca: AnsiString;
  const server_hostname: Variant): SSLSocket;
var host: AnsiString; err, fd, tmo: Integer; msg: array[0..255] of AnsiChar;
  h: Pointer; pca: PByte; r: SSLSocket; why: AnsiString; n: Integer;
  tv: Variant; secs: Double;
begin
  if IsNone(server_hostname) then host := '' else host := pystr_of(server_hostname);
  if (authmode = CERT_REQUIRED) and (host = '') then
    raise ValueError.Create('CERT_REQUIRED requires server_hostname');
  tmo := -1;
  tv := sock.gettimeout;
  if pystr_of(tv) <> 'None' then
  begin
    secs := tv;
    tmo := Round(secs * 1000);
    if (tmo = 0) and (secs > 0) then tmo := 1;
  end;
  fd := sock.detach;
  pca := nil;
  if Length(ca) > 0 then pca := PByte(PAnsiChar(ca));
  err := 0;
  msg[0] := #0;
  h := pxx_tls_connect(fd, PAnsiChar(host), authmode, pca, Length(ca), tmo,
    @err, @msg[0], 256);
  if h = nil then
  begin
    PalSocketClose(fd);   { MicroPython leaves the socket unusable too }
    if err = X509_VERIFY_FAILED then
    begin
      n := 0;
      while (n < 256) and (msg[n] <> #0) do n := n + 1;
      SetLength(why, n);
      if n > 0 then Move(msg[0], why[1], n);
      raise ValueError.Create(why);
    end;
    if (err <= X509_ANY_HI) and (err >= X509_ANY_LO) and (Length(ca) > 0)
       and (err <> X509_VERIFY_FAILED) then
      raise ValueError.Create('invalid cert');
    TlsFail('wrap_socket', err, tmo);
  end;
  r := SSLSocket.Adopt(fd, tmo);
  r.FTls := h;
  Connect := r;
end;

{ ---- SSLContext ----------------------------------------------------------- }

constructor SSLContext.Create(protocol: Integer);
begin
  FProtocol := protocol;
  verify_mode := CERT_NONE;   { micropython-lib ssl.py: SSLContext.__init__ }
  FCa := '';
end;

{ A CA that does not load is an ERROR here, never an empty trust store: a
  missing cafile raises OSError (errno 2, as CPython's FileNotFoundError), and
  a file or cadata with nothing in it raises ValueError. Data that is present
  but not a certificate raises ValueError('invalid cert') at wrap_socket,
  where mbedTLS parses it (pxx_tls_connect), whatever verify_mode is. And a
  CERT_REQUIRED context with NO CA refuses the handshake: mbedTLS answers
  MBEDTLS_ERR_SSL_CA_CHAIN_REQUIRED, surfaced as OSError. (frankuser,
  2026-09-28, after frankd-90 found the OpenSSL backend ignoring the load.) }
procedure SSLContext.load_verify_locations(const cafile: Variant; const cadata: Variant);
var f: TextFile; line, all, fn: AnsiString;
begin
  if not IsNone(cadata) then
  begin
    FCa := BytesOf(cadata);
    if Length(FCa) = 0 then raise ValueError.Create('invalid cert: cadata is empty');
  end
  else if not IsNone(cafile) then
  begin
    all := '';
    fn := pystr_of(cafile);
    if not FileExists(fn) then
      raise OSError.Create('(2, ''No such file or directory: ' + fn + ''')');
    AssignFile(f, fn);
    Reset(f);
    while not Eof(f) do
    begin
      ReadLn(f, line);
      all := all + line + #10;
    end;
    CloseFile(f);
    if Length(all) = 0 then raise ValueError.Create('invalid cert: ' + fn + ' is empty');
    FCa := all;
  end;
end;

procedure SSLContext.load_cert_chain(const certfile: Variant; const keyfile: Variant);
begin
  raise NotImplementedError.Create('ssl: client certificates are not supported (load_cert_chain)');
end;

function SSLContext.wrap_socket(sock: socket; server_side: Boolean;
  do_handshake_on_connect: Boolean; const server_hostname: Variant): SSLSocket;
begin
  if server_side or (FProtocol = PROTOCOL_TLS_SERVER) then
    raise NotImplementedError.Create('ssl: the server side is not supported');
  wrap_socket := Connect(sock, verify_mode, FCa, server_hostname);
end;

function wrap_socket(sock: socket; server_side: Boolean; const key: Variant;
  const cert: Variant; cert_reqs: Integer; const cadata: Variant;
  const server_hostname: Variant; do_handshake: Boolean): SSLSocket;
var ca: AnsiString;
begin
  if server_side then
    raise NotImplementedError.Create('ssl: the server side is not supported');
  if (not IsNone(key)) or (not IsNone(cert)) then
    raise NotImplementedError.Create('ssl: client certificates are not supported (key=, cert=)');
  ca := '';
  if not IsNone(cadata) then ca := BytesOf(cadata);
  wrap_socket := Connect(sock, cert_reqs, ca, server_hostname);
end;

end.
