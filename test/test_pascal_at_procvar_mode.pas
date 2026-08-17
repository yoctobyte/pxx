{ `@procvar` means different things in different modes, and FPC 3.2.2 is the
  oracle for both halves (mode names written bare below on purpose — a brace
  comment does not nest, so spelling them as directives would ARM them):

    delphi / tp        @p  ->  the code pointer p HOLDS
    objfpc / fpc       @p  ->  the ADDRESS OF p itself

  PXX did the objfpc thing unconditionally. That is right for its own dialect
  and wrong for Delphi-mode source, and the cost was not a diagnostic: Synapse
  forwards an OpenSSL callback as `_SslCtxSetVerify(ctx, mode, @arg2)` over a
  value parameter, so PXX handed OpenSSL the address of a live stack slot. It
  was stored, X509_verify_cert called it, and a TLS handshake jumped into the
  stack.
  bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert

  Asserted as RELATIONSHIPS, not addresses: a stack address is different every
  run, so the observable is whether @arg2 tracks the VALUE or the SLOT. }
program test_pascal_at_procvar_mode;

type
  PFunction = procedure;

var
  captured: PtrUInt;

procedure Capture(x: Pointer);
begin
  captured := PtrUInt(x);
end;

procedure Dummy;
begin
end;

{ @ over the parameter — the exact shape ssl_openssl3_lib.pas uses }
function AtOf(arg2: PFunction): PtrUInt;
begin
  Capture(@arg2);
  Result := captured;
end;

var
  atNil, atDummy, codeDummy: PtrUInt;
begin
  { `@Dummy` on a ROUTINE is a code address in every mode — the reference point.
    Deliberately not `Pointer(arg2)`: in delphi mode a bare procvar name means
    CALL IT, so that spelling does not compile there at all, which is the same
    rule this test is about seen from the other side. }
  Capture(@Dummy);
  codeDummy := captured;

  atNil   := AtOf(nil);
  atDummy := AtOf(@Dummy);

  { delphi: @arg2 IS the value -> 0 for nil, the code address for @Dummy
    objfpc: @arg2 is the SLOT  -> never 0, and the SAME whatever was passed }
  WriteLn(atNil = 0);
  WriteLn(atDummy = codeDummy);
  WriteLn(atNil = atDummy);
end.
