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

  Deliberately NOT a handshake. A TLS connect against a local server currently
  segfaults inside X509_verify_cert under pxx while the byte-identical program
  built with FPC completes it, and that is filed as a compiler bug. Asserting
  only what is TRUE today keeps this green and keeps the gap visible in its own
  ticket rather than as a mystery red here.

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
