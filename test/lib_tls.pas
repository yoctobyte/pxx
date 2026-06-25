program lib_tls;
{ Smoke for the backend-neutral TLS seam (feature-tls-provider-abstraction).
  Two things proved, no crypto:
    1. With NO backend registered, the neutral API fails cleanly (tlsError,
       TlsAvailable=False) -- never crashes.
    2. A mock *plaintext* backend (Read/Write just pass bytes over the fd)
       registered through the seam carries a real loopback round-trip end to
       end via TlsHandshake / TlsWrite / TlsRead / TlsClose. This exercises the
       vtable plumbing + the async-aware result contract -- the seam mechanics,
       independent of any real TLS. }
uses tls, sockets;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

type
  TMockConn = record fd: cint; end;
  PMockConn = ^TMockConn;

  { Plaintext passthrough masquerading as a TLS backend. }
  TMockTls = class(TTlsBackend)
    function  Name: string; override;
    function  Handshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): TTlsResult; override;
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; override;
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; override;
    procedure Close(c: TTlsConn); override;
  end;

function TMockTls.Name: string;
begin
  Result := 'mock';
end;

function TMockTls.Handshake(fd: Integer; role: TTlsRole; const host: string;
                            var c: TTlsConn): TTlsResult;
var p: PMockConn;
begin
  GetMem(p, SizeOf(TMockConn));
  p^.fd := fd;
  c := p;
  Result := tlsOk;
end;

function TMockTls.Read(c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult;
var n: Integer;
begin
  n := fpRecv(PMockConn(c)^.fd, buf, len, 0);
  if n > 0 then begin got := n; Result := tlsOk; end
  else if n = 0 then begin got := 0; Result := tlsClosed; end
  else begin got := 0; Result := tlsError; end;
end;

function TMockTls.Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult;
var n: Integer;
begin
  n := fpSend(PMockConn(c)^.fd, buf, len, 0);
  if n >= 0 then begin put := n; Result := tlsOk; end
  else begin put := 0; Result := tlsError; end;
end;

procedure TMockTls.Close(c: TTlsConn);
begin
  if c <> nil then FreeMem(c);
end;

const PORT = 28755;

var
  backend: TMockTls;
  noBackend: TTlsBackend;
  srv, cli, conn: cint;
  a: TInetSockAddr;
  alen: TSocklen;
  cc, sc: TTlsConn;
  sbuf, rbuf: array[0..31] of Byte;
  i, got, put, r: Integer;
  ok: Boolean;
begin
  { 1. No backend yet: neutral API must refuse cleanly. }
  SayBool('avail-none', not TlsAvailable);
  SayBool('active-nil', TlsActiveBackend = nil);
  cc := nil;
  r := Ord(TlsHandshake(0, tlsClient, 'example.com', cc));
  SayBool('handshake-noback', r = Ord(tlsError));
  SayBool('read-noback',  Ord(TlsRead(nil, @rbuf[0], 32, got)) = Ord(tlsError));
  SayBool('write-noback', Ord(TlsWrite(nil, @sbuf[0], 4, put)) = Ord(tlsError));

  { 2. Register the mock backend. }
  backend := TMockTls.Create;
  TlsRegisterBackend(backend);
  SayBool('avail-reg', TlsAvailable);
  SayBool('name-mock', TlsActiveBackend.Name = 'mock');

  { Loopback socket pair. }
  srv := fpSocket(AF_INET, SOCK_STREAM, 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(PORT);
  a.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  fpBind(srv, @a, SizeOf(TInetSockAddr));
  fpListen(srv, 4);
  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  fpConnect(cli, @a, SizeOf(TInetSockAddr));
  alen := SizeOf(TInetSockAddr);
  conn := fpAccept(srv, @a, @alen);
  SayBool('loopback-up', (cli >= 0) and (conn >= 0));

  { Handshake both ends through the seam (mock = no-op, returns tlsOk + conn). }
  SayBool('hs-client', TlsHandshake(cli,  tlsClient, 'localhost', cc) = tlsOk);
  SayBool('hs-server', TlsHandshake(conn, tlsServer, '',          sc) = tlsOk);

  { client -> server through TlsWrite / TlsRead }
  for i := 0 to 5 do sbuf[i] := i + 65;            { 'ABCDEF' }
  SayBool('tls-write', (TlsWrite(cc, @sbuf[0], 6, put) = tlsOk) and (put = 6));
  got := 0;
  SayBool('tls-read',  TlsRead(sc, @rbuf[0], 32, got) = tlsOk);
  ok := got = 6;
  for i := 0 to 5 do ok := ok and (rbuf[i] = i + 65);
  SayBool('roundtrip', ok);

  TlsClose(cc);
  TlsClose(sc);
  CloseSocket(cli); CloseSocket(conn); CloseSocket(srv);

  { Clearing the registry returns to the clean no-backend state. }
  noBackend := nil;
  TlsRegisterBackend(noBackend);
  SayBool('avail-cleared', not TlsAvailable);

  backend.Free;
end.
