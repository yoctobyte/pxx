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


var
  backend: TMockTls;
  noBackend: TTlsBackend;
  srv, cli, conn: cint;
  a: TInetSockAddr;
  alen: TSocklen;
  cc, sc: TTlsConn;
  sbuf, rbuf: array[0..31] of Byte;
  i, got, put, r: Integer;
  one: cint;
  rd: TFDSet;
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

  { Loopback socket pair, on an EPHEMERAL port.

    This used to bind a hardcoded 28755 and ignore the return of every socket
    call, and the result was not a flaky failure but a PERMANENT HANG
    (bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable): fpBind
    failed unnoticed, fpListen then implicitly bound some ephemeral port instead,
    fpConnect dialled 28755 and reached something else or nothing, and fpAccept
    waited forever for a connection nobody was ever going to make. It stopped
    dead at 7 of 14 =ok, so the TLS seam this test exists to check was never
    reached, and the only symptom was a testmgr TIMEOUT under a clean compile
    line — triaged three times as a possible TLS regression.

    A fixed port is a shared global. Two copies of this test on one box is all
    it takes, and that is not hypothetical: Track T's watcher host runs testmgr
    from two clones by design, where this job's EWMA was 45.4s over 46 runs
    against 2.4s over 16 in a dev clone. A test that takes one second does not
    average forty-five by being slow.

    Port 0 is the fix rather than SO_REUSEADDR because it makes the collision
    UNREPRESENTABLE instead of merely rarer: the kernel hands out a port nobody
    else holds, and fpGetSockName reads back which one. Checked returns and the
    accept deadline below are what turn any remaining fixture failure into a
    fast, named FAIL instead of a wait. }
  ok := True;
  srv := fpSocket(AF_INET, SOCK_STREAM, 0);
  ok := ok and (srv >= 0);
  one := 1;
  { Hygiene, not the fix: with port 0 there is nothing left to collide over, but
    a listener still in TIME_WAIT would otherwise refuse the rebind. }
  if ok then fpSetSockOpt(srv, SOL_SOCKET, SO_REUSEADDR, @one, SizeOf(one));
  a.sin_family := AF_INET;
  a.sin_port := htons(0);
  a.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  if ok then ok := fpBind(srv, @a, SizeOf(TInetSockAddr)) = 0;
  if ok then ok := fpListen(srv, 4) = 0;
  { Read back the port the kernel chose. Without this the client has nothing to
    dial — and note that skipping it would NOT be a clean error, because
    fpListen binds implicitly, so `a` would still hold port 0 and the connect
    would go somewhere else entirely. That is the original bug's second step. }
  alen := SizeOf(TInetSockAddr);
  if ok then ok := fpGetSockName(srv, @a, @alen) = 0;
  if ok then ok := ntohs(a.sin_port) <> 0;
  SayBool('fixture-listen', ok);

  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  if ok then ok := cli >= 0;
  if ok then ok := fpConnect(cli, @a, SizeOf(TInetSockAddr)) = 0;
  SayBool('fixture-connect', ok);

  { Accept with a DEADLINE. Even with every return checked, a blocking accept is
    a hang waiting for its next cause; five seconds is thousands of times the
    ~1s this whole test takes, so it can only fire on a broken fixture. }
  conn := -1;
  if ok then begin
    fpFD_ZERO(rd);
    fpFD_SET(srv, rd);
    ok := fpSelect(srv + 1, @rd, nil, nil, 5000) = 1;
    if ok then begin
      alen := SizeOf(TInetSockAddr);
      conn := fpAccept(srv, @a, @alen);
      ok := conn >= 0;
    end;
  end;
  SayBool('loopback-up', ok and (cli >= 0) and (conn >= 0));

  { A test that cannot build its own fixture must SAY SO AND STOP. Carrying on
    into the seam with bad descriptors is how a setup failure gets reported as a
    TLS failure, and waiting is how it got reported as nothing at all. }
  if not ok then begin
    writeln('fixture=FAIL (loopback pair could not be set up)');
    Halt(1);
  end;

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
