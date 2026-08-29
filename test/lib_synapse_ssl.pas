{ SPDX-License-Identifier: 0BSD }
program lib_synapse_ssl;
{ Synapse's OpenSSL 3 binding: it COMPILES, and the loader actually resolves
  real symbols out of a real libssl/libcrypto at run time.

  Two distinct things are asserted and they fail for different reasons.

  * `uses ssl_openssl3` compiling at all. It reaches `HModule` through
    synafpc -> dynlibs, and units do not re-export their imports transitively,
    so the type has to be visible the way FPC makes it visible — from SysUtils
    here, since pxx has no System unit. Before that landed this unit stopped
    with `unknown type: HModule` at its LoadLib/GetProcAddr helpers
    (feature-real-dynlib-loader).

  * `InitSSLInterface` + `OpenSSLVersion` answering. That is the dlopen loader
    proven end-to-end against a third-party .so we do not control, which is what
    that ticket exists for -- not a stub returning plausible zeros.

  Still NOT a handshake here -- but the reason has changed, and the old reason
  was left in place long enough to be worth correcting explicitly. It used to
  read "a TLS connect against a local server currently segfaults inside
  X509_verify_cert under pxx"; that was true, it was a compiler bug
  (bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert),
  and it was FIXED in 2ee660831 on 2026-08-17. A stale reason is worse than no
  reason: read today it says the compiler is broken when it is not, and it tells
  the next person the gap is someone else's to close.

  Measured 2026-08-29 against pinned v391, x86-64, OpenSSL 3.5.5,
  -dPXX_DYNLIB_LIBC, with `openssl s_server` on a self-signed localhost cert:
  `connect=0 ssl=0`, five runs out of five, and the FPC oracle built from the
  same source gives the identical `connect=0 ssl=0`. The handshake works.

  It is absent from this program for a purely mechanical reason: a TLS handshake
  is a CONVERSATION, so a hermetic loopback needs both sides live at once, and
  this suite is single-process with no fork primitive. Doing it properly means a
  self-exec harness (the test re-runs its own binary as the server, cert via
  TSSLOpenSSL.CreateSelfSignedCert), which is real test infrastructure and is
  filed as feature-b-a-hermetic-tls-loopback-for-the-ssl-suite rather than
  bolted in here as a flaky openssl-CLI dependency inside Track B's gate.
  The 30-second manual repro is recorded in feature-real-dynlib-loader.

  Needs -dPXX_DYNLIB_LIBC (the opt-in libc-linked loader) and external/synapse. }

{$MODE DELPHI}

uses sysutils, ssl_openssl3, ssl_openssl3_lib;

var
  v: string;
  h: HModule;
begin
  { the type whose absence used to stop this unit compiling }
  h := 0;
  if h <> 0 then WriteLn('unreachable');
  WriteLn('hmodule=ok');

  if not InitSSLInterface then
  begin
    WriteLn('init=FAIL');
    Halt(1);
  end;
  WriteLn('init=ok');

  v := OpenSSLVersion(0);
  { real libcrypto answers with its own banner; a stub would answer '' }
  if Pos('OpenSSL', v) = 1 then
    WriteLn('version=ok')
  else
    WriteLn('version=FAIL ', v);

  WriteLn('SYNAPSE-SSL OK');
end.
