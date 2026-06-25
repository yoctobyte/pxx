unit tls_openssl;
{ OpenSSL backend for the TLS seam (feature-tls-provider-abstraction, the OpenSSL
  half). Loads libssl.so.3 at runtime through the real dynlib loader
  (feature-real-dynlib-loader) and implements TTlsBackend over SSL_*.

  Opt-in: this unit is only useful in a build that has the real loader
  (-dPXX_DYNLIB_LIBC); without it dynlibs' LoadLibrary returns NilHandle and
  OpenSslTlsRegister returns False (caller stays plaintext / no TLS). x86-64 only
  for now (that is where the loader is verified).

  Scope of this slice: a working **client**. SSL_connect is driven to completion
  inside Handshake (poll loop), which is correct for a BLOCKING socket fd (the
  http blocking path). The async (reactor) path needs a non-blocking handshake
  resume step on the seam first; until then use the OpenSSL backend with the
  blocking HttpGet/HttpExec family.

  Security: verification mode is left at OpenSSL's client default (no peer-cert
  verification) for now, matching the platonic/dev focus — DO NOT use this as-is
  against hostile networks without wiring SSL_CTX_set_verify + a trust store. }

interface

uses tls;

{ dlopen libssl, build a client SSL_CTX, register an OpenSSL TTlsBackend as the
  active TLS backend. True on success; False if the loader/lib is unavailable. }
function OpenSslTlsRegister: Boolean;

{ Drop the backend + free the SSL_CTX (does not unload the library). }
procedure OpenSslTlsUnregister;

implementation

uses dynlibs, platform;

const
  SSL_ERROR_WANT_READ  = 2;
  SSL_ERROR_WANT_WRITE = 3;
  SSL_ERROR_ZERO_RETURN = 6;
  SSL_CTRL_SET_TLSEXT_HOSTNAME = 55;
  TLSEXT_NAMETYPE_host_name = 0;

type
  { OpenSSL function pointers. Plain (non-cdecl) proc vars: on x86-64 the default
    call ABI matches the System V cdecl used by libssl for these pointer/int
    signatures (same as dynlibs' strlen smoke). }
  TMethodFn   = function: Pointer;
  TCtxNewFn   = function(method: Pointer): Pointer;
  TCtxFreeFn  = procedure(ctx: Pointer);
  TSslNewFn   = function(ctx: Pointer): Pointer;
  TSslFreeFn  = procedure(ssl: Pointer);
  TSetFdFn    = function(ssl: Pointer; fd: Integer): Integer;
  TConnectFn  = function(ssl: Pointer): Integer;
  TRwFn       = function(ssl: Pointer; buf: Pointer; num: Integer): Integer;
  TGetErrFn   = function(ssl: Pointer; ret: Integer): Integer;
  TShutdownFn = function(ssl: Pointer): Integer;
  TCtrlFn     = function(ssl: Pointer; cmd: Integer; larg: Int64; parg: Pointer): Int64;

  TSslConn = record ssl: Pointer; fd: Integer; end;
  PSslConn = ^TSslConn;

  TOpenSslTls = class(TTlsBackend)
    function  Name: string; override;
    function  Handshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): TTlsResult; override;
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; override;
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; override;
    procedure Close(c: TTlsConn); override;
  end;

var
  gLib:       TLibHandle;
  gCtx:       Pointer;
  gBackend:   TOpenSslTls;
  { resolved entry points }
  pTlsClientMethod: TMethodFn;
  pCtxNew:    TCtxNewFn;
  pCtxFree:   TCtxFreeFn;
  pSslNew:    TSslNewFn;
  pSslFree:   TSslFreeFn;
  pSetFd:     TSetFdFn;
  pConnect:   TConnectFn;
  pRead:      TRwFn;
  pWrite:     TRwFn;
  pGetErr:    TGetErrFn;
  pShutdown:  TShutdownFn;
  pCtrl:      TCtrlFn;

function ResolveAll: Boolean;
begin
  pTlsClientMethod := TMethodFn  (GetProcedureAddress(gLib, 'TLS_client_method'));
  pCtxNew    := TCtxNewFn  (GetProcedureAddress(gLib, 'SSL_CTX_new'));
  pCtxFree   := TCtxFreeFn (GetProcedureAddress(gLib, 'SSL_CTX_free'));
  pSslNew    := TSslNewFn  (GetProcedureAddress(gLib, 'SSL_new'));
  pSslFree   := TSslFreeFn (GetProcedureAddress(gLib, 'SSL_free'));
  pSetFd     := TSetFdFn   (GetProcedureAddress(gLib, 'SSL_set_fd'));
  pConnect   := TConnectFn (GetProcedureAddress(gLib, 'SSL_connect'));
  pRead      := TRwFn      (GetProcedureAddress(gLib, 'SSL_read'));
  pWrite     := TRwFn      (GetProcedureAddress(gLib, 'SSL_write'));
  pGetErr    := TGetErrFn  (GetProcedureAddress(gLib, 'SSL_get_error'));
  pShutdown  := TShutdownFn(GetProcedureAddress(gLib, 'SSL_shutdown'));
  pCtrl      := TCtrlFn    (GetProcedureAddress(gLib, 'SSL_ctrl'));
  Result := (pTlsClientMethod <> nil) and (pCtxNew <> nil) and (pSslNew <> nil)
        and (pSetFd <> nil) and (pConnect <> nil) and (pRead <> nil)
        and (pWrite <> nil) and (pGetErr <> nil) and (pShutdown <> nil)
        and (pSslFree <> nil) and (pCtrl <> nil);
end;

function TOpenSslTls.Name: string;
begin Result := 'openssl'; end;

function TOpenSslTls.Handshake(fd: Integer; role: TTlsRole; const host: string;
                               var c: TTlsConn): TTlsResult;
var p: PSslConn; ssl: Pointer; ret, err: Integer;
begin
  c := nil;
  Result := tlsError;
  if gCtx = nil then Exit;
  ssl := pSslNew(gCtx);
  if ssl = nil then Exit;
  pSetFd(ssl, fd);
  if host <> '' then
    pCtrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, Pointer(PChar(host)));

  { drive SSL_connect to completion (one call on a blocking fd; poll-loop covers
    a non-blocking fd too, blocking the thread — fine for the blocking path) }
  repeat
    ret := pConnect(ssl);
    if ret = 1 then
    begin
      GetMem(p, SizeOf(TSslConn));
      p^.ssl := ssl; p^.fd := fd;
      c := p;
      Result := tlsOk;
      Exit;
    end;
    err := pGetErr(ssl, ret);
    if err = SSL_ERROR_WANT_READ then PalPoll(fd, PAL_POLL_IN, -1)
    else if err = SSL_ERROR_WANT_WRITE then PalPoll(fd, PAL_POLL_OUT, -1)
    else begin pSslFree(ssl); Exit; end;
  until False;
end;

function TOpenSslTls.Read(c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult;
var n, err: Integer;
begin
  got := 0;
  n := pRead(PSslConn(c)^.ssl, buf, len);
  if n > 0 then begin got := n; Result := tlsOk; Exit; end;
  err := pGetErr(PSslConn(c)^.ssl, n);
  if err = SSL_ERROR_WANT_READ then Result := tlsWantRead
  else if err = SSL_ERROR_WANT_WRITE then Result := tlsWantWrite
  else if err = SSL_ERROR_ZERO_RETURN then Result := tlsClosed
  else Result := tlsError;
end;

function TOpenSslTls.Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult;
var n, err: Integer;
begin
  put := 0;
  n := pWrite(PSslConn(c)^.ssl, buf, len);
  if n > 0 then begin put := n; Result := tlsOk; Exit; end;
  err := pGetErr(PSslConn(c)^.ssl, n);
  if err = SSL_ERROR_WANT_READ then Result := tlsWantRead
  else if err = SSL_ERROR_WANT_WRITE then Result := tlsWantWrite
  else Result := tlsError;
end;

procedure TOpenSslTls.Close(c: TTlsConn);
var p: PSslConn;
begin
  if c = nil then Exit;
  p := PSslConn(c);
  if p^.ssl <> nil then begin pShutdown(p^.ssl); pSslFree(p^.ssl); end;
  FreeMem(p);
end;

function OpenSslTlsRegister: Boolean;
begin
  Result := False;
  if gBackend <> nil then begin Result := True; Exit; end;   { already up }
  gLib := LoadLibrary('libssl.so.3');
  if gLib = NilHandle then Exit;                              { no loader / no lib }
  if not ResolveAll then Exit;
  gCtx := pCtxNew(pTlsClientMethod());
  if gCtx = nil then Exit;
  gBackend := TOpenSslTls.Create;
  TlsRegisterBackend(gBackend);
  Result := True;
end;

procedure OpenSslTlsUnregister;
var none: TTlsBackend;
begin
  none := nil;
  TlsRegisterBackend(none);
  if gCtx <> nil then begin if pCtxFree <> nil then pCtxFree(gCtx); gCtx := nil; end;
  if gBackend <> nil then begin gBackend.Free; gBackend := nil; end;
end;

begin
  gLib := NilHandle; gCtx := nil; gBackend := nil;
end.
