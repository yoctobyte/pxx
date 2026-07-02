{ SPDX-License-Identifier: Zlib }
unit tls;
{ Backend-neutral TLS seam (feature-tls-provider-abstraction).

  Any net code (http, future servers) talks to this contract instead of raw
  NetSend/NetRecv, so a TLS backend can be swapped underneath without touching
  callers. Two backends are planned behind this one interface:

    * OpenSSL (dlopen libssl/libcrypto)  -- the safe default; needs the real
      dynlib loader (feature-real-dynlib-loader).
    * a handrolled syscall-only TLS 1.3  -- the platonic native stack
      (feature-tls13-from-scratch, deferred).

  This unit is just the seam + a registry; it ships NO backend. With no backend
  registered, the neutral wrappers fail cleanly with tlsError (never crash) --
  exactly how `dynlibs` honestly reports "no loader".

  The Read/Write contract is async-aware: backends return tlsWantRead /
  tlsWantWrite (OpenSSL's WANT_READ/WANT_WRITE, the native stack's equivalent) so
  an async caller maps them to WaitReadable/WaitWritable and yields its coroutine;
  a blocking caller loops on poll. One contract serves both transports. }

interface

type
  TTlsRole = (tlsClient, tlsServer);

  { Outcome of a handshake / read / write step. tlsWantRead/tlsWantWrite mean
    "would block": retry after the socket is readable/writable. }
  TTlsResult = (tlsOk, tlsWantRead, tlsWantWrite, tlsClosed, tlsError);

  { Opaque, backend-defined per-connection handle. Callers never inspect it. }
  TTlsConn = Pointer;

  { A backend = a vtable implementing the handshake + record I/O over a connected
    socket fd. Base methods default to tlsError so a partially-implemented or
    absent backend degrades gracefully rather than crashing. }
  TTlsBackend = class
    { Human-readable backend name, e.g. 'openssl' / 'native' / 'mock'. }
    function  Name: string; virtual;
    { Begin the TLS handshake over an already-connected `fd`. `host` feeds SNI /
      cert-name verification for clients. NON-BLOCKING: on `tlsOk`, `c` is a live
      connection; on `tlsWantRead`/`tlsWantWrite`, `c` is allocated but the
      handshake is incomplete — the caller waits for the fd then calls
      `HandshakeResume(c)` until it no longer wants I/O. On `tlsError`, `c` is nil.
      (A backend over a blocking fd simply returns `tlsOk`/`tlsError` and never
      wants — the resume loop is then a no-op.) }
    function  Handshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): TTlsResult; virtual;
    { Continue a handshake that returned want-read/want-write, after the fd became
      ready. Returns `tlsOk` when complete, another want, or `tlsError`. }
    function  HandshakeResume(c: TTlsConn): TTlsResult; virtual;
    { Decrypt up to `len` bytes into `buf`; `got` = bytes produced. }
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; virtual;
    { Encrypt+send up to `len` bytes from `buf`; `put` = bytes consumed. }
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; virtual;
    { Close the TLS layer and release the handle (not the fd). }
    procedure Close(c: TTlsConn); virtual;
  end;

{ --- registry: one process-global default backend --- }

{ Install `b` as the active backend (replaces any previous). Pass nil to clear. }
procedure TlsRegisterBackend(b: TTlsBackend);
{ The active backend, or nil if none registered. }
function  TlsActiveBackend: TTlsBackend;
{ True iff a backend is registered (the `https://` enabler check). }
function  TlsAvailable: Boolean;

{ --- neutral API over the active backend (fail cleanly when none) --- }

function  TlsHandshake(fd: Integer; role: TTlsRole; const host: string;
                       var c: TTlsConn): TTlsResult;
function  TlsHandshakeResume(c: TTlsConn): TTlsResult;
function  TlsRead (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult;
function  TlsWrite(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult;
procedure TlsClose(c: TTlsConn);

implementation

var
  gBackend: TTlsBackend;

{ ----- TTlsBackend graceful defaults ----- }

function TTlsBackend.Name: string;
begin
  Result := 'none';
end;

function TTlsBackend.Handshake(fd: Integer; role: TTlsRole; const host: string;
                               var c: TTlsConn): TTlsResult;
begin
  c := nil;
  Result := tlsError;
end;

function TTlsBackend.HandshakeResume(c: TTlsConn): TTlsResult;
begin
  Result := tlsError;
end;

function TTlsBackend.Read(c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult;
begin
  got := 0;
  Result := tlsError;
end;

function TTlsBackend.Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult;
begin
  put := 0;
  Result := tlsError;
end;

procedure TTlsBackend.Close(c: TTlsConn);
begin
  { nothing }
end;

{ ----- registry ----- }

procedure TlsRegisterBackend(b: TTlsBackend);
begin
  gBackend := b;
end;

function TlsActiveBackend: TTlsBackend;
begin
  Result := gBackend;
end;

function TlsAvailable: Boolean;
begin
  Result := gBackend <> nil;
end;

{ ----- neutral API ----- }

function TlsHandshake(fd: Integer; role: TTlsRole; const host: string;
                      var c: TTlsConn): TTlsResult;
begin
  c := nil;
  if gBackend = nil then
    Result := tlsError
  else
    Result := gBackend.Handshake(fd, role, host, c);
end;

function TlsHandshakeResume(c: TTlsConn): TTlsResult;
begin
  if gBackend = nil then
    Result := tlsError
  else
    Result := gBackend.HandshakeResume(c);
end;

function TlsRead(c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult;
begin
  got := 0;
  if gBackend = nil then
    Result := tlsError
  else
    Result := gBackend.Read(c, buf, len, got);
end;

function TlsWrite(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult;
begin
  put := 0;
  if gBackend = nil then
    Result := tlsError
  else
    Result := gBackend.Write(c, buf, len, put);
end;

procedure TlsClose(c: TTlsConn);
begin
  if gBackend <> nil then
    gBackend.Close(c);
end;

begin
  gBackend := nil;
end.
