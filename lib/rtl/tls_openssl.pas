{ SPDX-License-Identifier: Zlib }
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
  active TLS backend. True on success; False if the loader/lib is unavailable.

  OpenSslTlsRegister is the secure default: verify the peer certificate against
  the system trust store and match the connection hostname (CN/SAN). Use
  OpenSslTlsRegisterEx to add a private/test CA or to turn verification off. }
function OpenSslTlsRegister: Boolean;
function OpenSslTlsRegisterEx(verifyPeer: Boolean; const caFile: string): Boolean;

{ Enable the server role: build a server SSL_CTX from a PEM cert + private key.
  Shares the one active backend with the client side, so a process can serve TLS
  and make TLS client requests at once. True when cert + key load. }
function OpenSslTlsServerInit(const certFile, keyFile: string): Boolean;

{ X509_V_* code from the most recent failed handshake (0 = X509_V_OK). Lets a
  caller report *why* a TLS connection was rejected. }
function OpenSslTlsLastVerifyResult: Int64;

{ Drop the backend + free the SSL_CTX (does not unload the library). }
procedure OpenSslTlsUnregister;

implementation

uses dynlibs;

const
  SSL_ERROR_WANT_READ  = 2;
  SSL_ERROR_WANT_WRITE = 3;
  SSL_ERROR_ZERO_RETURN = 6;
  SSL_CTRL_SET_TLSEXT_HOSTNAME = 55;
  TLSEXT_NAMETYPE_host_name = 0;
  SSL_VERIFY_NONE = 0;
  SSL_VERIFY_PEER = 1;
  X509_V_OK = 0;
  SSL_FILETYPE_PEM = 1;

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
  TSetVerifyFn = procedure(ctx: Pointer; mode: Integer; cb: Pointer);
  TDefPathsFn  = function(ctx: Pointer): Integer;
  TLoadVerifyFn = function(ctx: Pointer; CAfile: PChar; CApath: PChar): Integer;
  TSet1HostFn  = function(ssl: Pointer; name: PChar): Integer;
  TVerifyResFn = function(ssl: Pointer): Int64;
  TUseFileFn   = function(ctx: Pointer; fname: PChar; ftype: Integer): Integer;

  TSslConn = record ssl: Pointer; fd: Integer; isServer: Boolean; end;
  PSslConn = ^TSslConn;

  TOpenSslTls = class(TTlsBackend)
    function  Name: string; override;
    function  Handshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): TTlsResult; override;
    function  HandshakeResume(c: TTlsConn): TTlsResult; override;
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; override;
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; override;
    procedure Close(c: TTlsConn); override;
  end;

var
  gLib:       TLibHandle;
  gClientCtx: Pointer;          { client SSL_CTX (TLS_client_method) }
  gServerCtx: Pointer;          { server SSL_CTX (TLS_server_method + cert/key) }
  gBackend:   TOpenSslTls;
  gVerify:    Boolean;          { client peer + hostname verification on? }
  gLastVerifyResult: Int64;     { X509_V_* from the last failed handshake }
  { resolved entry points }
  pTlsClientMethod: TMethodFn;
  pTlsServerMethod: TMethodFn;
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
  pSetVerify: TSetVerifyFn;
  pDefPaths:  TDefPathsFn;
  pLoadVerify: TLoadVerifyFn;
  pSet1Host:  TSet1HostFn;
  pVerifyRes: TVerifyResFn;
  pAccept:    TConnectFn;       { SSL_accept (same shape as SSL_connect) }
  pUseCert:   TUseFileFn;
  pUseKey:    TUseFileFn;

function ResolveAll: Boolean;
begin
  pTlsClientMethod := TMethodFn  (GetProcedureAddress(gLib, 'TLS_client_method'));
  pTlsServerMethod := TMethodFn  (GetProcedureAddress(gLib, 'TLS_server_method'));
  pAccept    := TConnectFn (GetProcedureAddress(gLib, 'SSL_accept'));
  pUseCert   := TUseFileFn (GetProcedureAddress(gLib, 'SSL_CTX_use_certificate_file'));
  pUseKey    := TUseFileFn (GetProcedureAddress(gLib, 'SSL_CTX_use_PrivateKey_file'));
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
  pSetVerify := TSetVerifyFn (GetProcedureAddress(gLib, 'SSL_CTX_set_verify'));
  pDefPaths  := TDefPathsFn  (GetProcedureAddress(gLib, 'SSL_CTX_set_default_verify_paths'));
  pLoadVerify := TLoadVerifyFn(GetProcedureAddress(gLib, 'SSL_CTX_load_verify_locations'));
  pSet1Host  := TSet1HostFn  (GetProcedureAddress(gLib, 'SSL_set1_host'));
  pVerifyRes := TVerifyResFn (GetProcedureAddress(gLib, 'SSL_get_verify_result'));
  Result := (pTlsClientMethod <> nil) and (pTlsServerMethod <> nil)
        and (pCtxNew <> nil) and (pSslNew <> nil)
        and (pSetFd <> nil) and (pConnect <> nil) and (pAccept <> nil)
        and (pRead <> nil) and (pWrite <> nil) and (pGetErr <> nil)
        and (pShutdown <> nil) and (pSslFree <> nil) and (pCtrl <> nil)
        and (pSetVerify <> nil) and (pDefPaths <> nil) and (pLoadVerify <> nil)
        and (pSet1Host <> nil) and (pVerifyRes <> nil)
        and (pUseCert <> nil) and (pUseKey <> nil);
end;

function TOpenSslTls.Name: string;
begin Result := 'openssl'; end;

{ One handshake step (SSL_connect for a client, SSL_accept for a server), mapped
  to a seam result. tlsOk = complete; want = needs the fd ready then another step;
  tlsError = fatal. }
function SslStepHandshake(p: PSslConn): TTlsResult;
var ret, err: Integer;
begin
  if p^.isServer then ret := pAccept(p^.ssl) else ret := pConnect(p^.ssl);
  if ret = 1 then begin Result := tlsOk; Exit; end;
  err := pGetErr(p^.ssl, ret);
  if err = SSL_ERROR_WANT_READ then Result := tlsWantRead
  else if err = SSL_ERROR_WANT_WRITE then Result := tlsWantWrite
  else Result := tlsError;
end;

function TOpenSslTls.Handshake(fd: Integer; role: TTlsRole; const host: string;
                               var c: TTlsConn): TTlsResult;
var p: PSslConn; ssl, ctx: Pointer; isSrv: Boolean;
begin
  c := nil;
  Result := tlsError;
  isSrv := role = tlsServer;
  if isSrv then ctx := gServerCtx else ctx := gClientCtx;
  if ctx = nil then Exit;
  ssl := pSslNew(ctx);
  if ssl = nil then Exit;
  pSetFd(ssl, fd);
  if (not isSrv) and (host <> '') then
  begin
    pCtrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, Pointer(PChar(host)));
    { enable hostname match against the cert during verification }
    if gVerify then pSet1Host(ssl, PChar(host));
  end;

  GetMem(p, SizeOf(TSslConn));
  p^.ssl := ssl; p^.fd := fd; p^.isServer := isSrv;

  { NON-blocking: one step. On a blocking fd this returns tlsOk immediately; on a
    non-blocking fd it may return want, and the caller drives HandshakeResume. }
  Result := SslStepHandshake(p);
  if Result = tlsError then
  begin
    if not isSrv then gLastVerifyResult := pVerifyRes(ssl);   { X509_V_* — why }
    pSslFree(ssl); FreeMem(p); c := nil;
  end
  else
    c := p;                 { tlsOk or want — connection lives }
end;

function TOpenSslTls.HandshakeResume(c: TTlsConn): TTlsResult;
begin
  if c = nil then begin Result := tlsError; Exit; end;
  Result := SslStepHandshake(PSslConn(c));
  if (Result = tlsError) and (not PSslConn(c)^.isServer) then
    gLastVerifyResult := pVerifyRes(PSslConn(c)^.ssl);
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

{ Load libssl + resolve symbols + register the (single) OpenSSL backend as active.
  Idempotent: a process can be both client and server on the one backend. }
function EnsureBackend: Boolean;
begin
  if gBackend <> nil then begin Result := True; Exit; end;
  Result := False;
  gLib := LoadLibrary('libssl.so.3');
  if gLib = NilHandle then Exit;                              { no loader / no lib }
  if not ResolveAll then Exit;
  gBackend := TOpenSslTls.Create;
  TlsRegisterBackend(gBackend);
  Result := True;
end;

function OpenSslTlsRegisterEx(verifyPeer: Boolean; const caFile: string): Boolean;
begin
  Result := False;
  if not EnsureBackend then Exit;
  if gClientCtx = nil then gClientCtx := pCtxNew(pTlsClientMethod());
  if gClientCtx = nil then Exit;

  { trust store: the system default CA bundle, plus an optional extra CA file
    (a private/test CA). Verification mode is per the caller. }
  pDefPaths(gClientCtx);
  if caFile <> '' then pLoadVerify(gClientCtx, PChar(caFile), nil);
  if verifyPeer then pSetVerify(gClientCtx, SSL_VERIFY_PEER, nil)
  else pSetVerify(gClientCtx, SSL_VERIFY_NONE, nil);
  gVerify := verifyPeer;
  gLastVerifyResult := X509_V_OK;
  Result := True;
end;

function OpenSslTlsRegister: Boolean;
begin
  { secure default: verify the peer against the system trust store + match the
    hostname. Use OpenSslTlsRegisterEx for a private CA or to opt out. }
  Result := OpenSslTlsRegisterEx(True, '');
end;

function OpenSslTlsServerInit(const certFile, keyFile: string): Boolean;
begin
  Result := False;
  if not EnsureBackend then Exit;
  if gServerCtx = nil then gServerCtx := pCtxNew(pTlsServerMethod());
  if gServerCtx = nil then Exit;
  if pUseCert(gServerCtx, PChar(certFile), SSL_FILETYPE_PEM) <> 1 then Exit;
  if pUseKey (gServerCtx, PChar(keyFile),  SSL_FILETYPE_PEM) <> 1 then Exit;
  Result := True;
end;

function OpenSslTlsLastVerifyResult: Int64;
begin
  Result := gLastVerifyResult;
end;

procedure OpenSslTlsUnregister;
var none: TTlsBackend;
begin
  none := nil;
  TlsRegisterBackend(none);
  if gClientCtx <> nil then begin if pCtxFree <> nil then pCtxFree(gClientCtx); gClientCtx := nil; end;
  if gServerCtx <> nil then begin if pCtxFree <> nil then pCtxFree(gServerCtx); gServerCtx := nil; end;
  if gBackend <> nil then begin gBackend.Free; gBackend := nil; end;
end;

begin
  gLib := NilHandle; gClientCtx := nil; gServerCtx := nil; gBackend := nil;
end.
