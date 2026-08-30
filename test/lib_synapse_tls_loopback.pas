{ SPDX-License-Identifier: 0BSD }
program lib_synapse_tls_loopback;
{ A hermetic TLS handshake, both sides ours, no network and no external CLI.
  feature-b-a-hermetic-tls-loopback-for-the-ssl-suite

  lib_synapse_ssl proves the dlopen'd libssl resolves real symbols. It does NOT
  prove a handshake completes, and a handshake is the only thing that drives a
  third-party C library through a full protocol conversation. The crash this
  guards against was a COMPILER bug -- a tail call through a function pointer
  holding a stack address, inside X509_verify_cert
  (bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert,
  fixed 2ee660831). Nothing in Track B's gate exercised it, so a recurrence
  would have surfaced as a segfault in whichever application hit it first.

  SELF-EXEC, because a handshake is a CONVERSATION: both ends must be live at
  once, this suite is single-process, and lib/rtl has no fork. So the test
  re-runs ITS OWN binary as the server (ExecutePipeline(ParamStr(0), ...)),
  the child binds an ephemeral port and writes it back over the pipe, and the
  parent connects. No openssl CLI, no cert file, no fixed port, no expiry to
  rot, and no extra Makefile wiring because the child is this same binary.

  The cert is created by ssl_openssl3 itself: Prepare() calls
  CreateSelfSignedCert for a server socket with no cert configured. That method
  is protected, so this is the supported way to reach it.

  TWO handshakes, and the second is the one with teeth:

    * VerifyCert=False -- the handshake COMPLETES and application data crosses
      it. Proves the conversation works end to end.

    * VerifyCert=True  -- the handshake is REJECTED, `certificate verify
      failed`, because the cert is self-signed and untrusted.

  Only the second proves X509_verify_cert actually RAN. A permissive handshake
  can complete without the verification path ever reaching a decision, which
  would leave this test green while the code it exists to guard was never
  entered -- a green that guards nothing. The rejection is the positive
  evidence, and its error string is asserted, not just its failure.

  Timing: measured 80/80 green (40 serial, 40 as eight concurrent) at ~625ms
  on a box loaded at 13 on 12 cores. Every wait is bounded -- the child's
  accept, both socket timeouts, and the parent's port read, which unblocks on
  the child's EOF if the child dies -- because lib-test runs against a 600s
  ceiling in agent harnesses and a HANG is the one failure mode that would be
  indistinguishable from that artifact.

  Needs external/synapse (the Makefile guards it) and a real libssl reachable
  through -dPXX_DYNLIB_LIBC; without libssl it exits SKIP_EXIT and the recipe
  reports a skip rather than a silent pass. }

{$MODE DELPHI}

uses sysutils, blcksock, ssl_openssl3, ssl_openssl3_lib;

const
  SERVER_ARG = '--tls-server';
  ACCEPT_MS  = 10000;
  IO_MS      = 10000;
  SKIP_EXIT  = 77;

var
  bad: Integer = 0;

procedure Check(const label_: AnsiString; ok: Boolean; const detail: AnsiString);
begin
  if ok then WriteLn(label_, '=ok')
  else begin WriteLn(label_, '=FAIL ', detail); Inc(bad); end;
end;

{ the child half: bind, publish the port, accept ONE TLS connection }
procedure RunServer;
var srv, conn: TTCPBlockSocket;
begin
  srv := TTCPBlockSocket.Create;
  try
    srv.Bind('127.0.0.1', '0');       { ephemeral: no fixed port to collide }
    srv.Listen;
    WriteLn(srv.GetLocalSinPort);
    Flush(Output);                    { stdout is a pipe here -- buffered }
    if not srv.CanRead(ACCEPT_MS) then Halt(2);
    conn := TTCPBlockSocket.Create;
    try
      conn.Socket := srv.Accept;
      if not conn.SSLAcceptConnection then Halt(3);
      conn.SendString('pong' + CRLF);
      conn.CloseSocket;
    finally conn.Free; end;
  finally srv.Free; end;
end;

{ one full round trip against a freshly spawned server. Returns False only for
  harness failures (spawn/port); a rejected handshake is a RESULT, not an error,
  and is reported through sslErr. }
function Handshake(verify: Boolean; var sslErr: Integer;
               var sslDesc, payload: AnsiString): Boolean;
var
  inFd, outFd, pid, n, i, waited: Integer;
  buf: array[0..255] of Byte;
  port: AnsiString;
  cli: TTCPBlockSocket;
begin
  Handshake := False;
  sslErr := -1; sslDesc := ''; payload := '';
  { -1 REQUESTS a pipe. Any other value is read as an fd the caller already
    owns, so leaving these uninitialised hands the child our terminal and the
    parent then blocks on a pipe nothing will ever write to. }
  inFd := -1; outFd := -1;
  pid := ExecutePipeline(ParamStr(0), [SERVER_ARG], inFd, outFd);
  if pid <= 0 then Exit;

  { bounded: the child's own ACCEPT_MS guarantees EOF here even if it wedges }
  port := ''; waited := 0;
  while (Pos(#10, port) = 0) and (waited < 200) do
  begin
    for i := 0 to 255 do buf[i] := 0;
    n := PalRead(outFd, @buf[0], 256);
    if n > 0 then
      for i := 0 to n - 1 do port := port + Chr(buf[i])
    else if n = 0 then Break            { child exited without publishing }
    else begin Inc(waited); Sleep(25); end;
  end;
  port := Trim(port);
  if port = '' then Exit;

  cli := TTCPBlockSocket.Create;
  try
    cli.ConnectionTimeout := IO_MS;
    cli.Connect('127.0.0.1', port);
    if cli.LastError <> 0 then Exit;
    cli.SSL.VerifyCert := verify;
    { SSLDoConnect is a PROCEDURE -- the verdict is LastError, which is what
      the manual probe's `connect=0 ssl=0` was reading }
    cli.SSLDoConnect;
    sslErr := cli.LastError;
    sslDesc := cli.SSL.LastErrorDesc;
    if sslErr = 0 then payload := Trim(cli.RecvString(IO_MS));
    Handshake := True;
  finally cli.Free; end;
end;

var
  err: Integer;
  desc, payload: AnsiString;
begin
  if (ParamCount >= 1) and (ParamStr(1) = SERVER_ARG) then
  begin RunServer; Exit; end;

  if not InitSSLInterface then
  begin
    WriteLn('no usable libssl/libcrypto at run time');
    Halt(SKIP_EXIT);
  end;

  { 1. permissive: the conversation must complete and carry data }
  if not Handshake(False, err, desc, payload) then
  begin WriteLn('harness=FAIL could not spawn/reach the server child'); Halt(1); end;
  WriteLn('harness=ok');
  Check('ssl', err = 0, IntToStr(err) + ' ' + desc);
  Check('data', payload = 'pong', '[' + payload + ']');

  { 2. verifying: a self-signed cert must be REJECTED. This is the arm that
       proves X509_verify_cert ran; without it a green here would be
       compatible with the verification path never being entered. }
  if not Handshake(True, err, desc, payload) then
  begin WriteLn('harness2=FAIL could not spawn/reach the server child'); Halt(1); end;
  WriteLn('harness2=ok');
  Check('verify-rejects', err <> 0, 'handshake ACCEPTED an untrusted self-signed cert');
  Check('verify-reason', Pos('certificate verify failed', desc) > 0, desc);

  if bad > 0 then Halt(1);
  WriteLn('TLS-LOOPBACK OK');
end.
