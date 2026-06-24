program lib_dynlibs;
{ Smoke for the honest-stub dynlibs unit (feature-synapse-compile-check).
  No runtime loader on the libc-free target, so LoadLibrary -> NilHandle and
  GetProcedureAddress -> nil. Asserts the stub contract callers (Synapse) rely
  on; update when feature-real-dynlib-loader gives this a real backend. }
uses dynlibs;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var
  h: TLibHandle;
  p: Pointer;
begin
  h := LoadLibrary('libssl.so');
  SayBool('nil-handle', h = NilHandle);

  p := GetProcedureAddress(h, 'SSL_new');
  SayBool('sym-nil', p = nil);

  SayBool('procaddr-alias', GetProcAddress(h, 'SSL_new') = nil);

  { Unloading a NilHandle is a no-op success. }
  SayBool('unload', UnloadLibrary(h));
  SayBool('free-alias', FreeLibrary(h));

  SayBool('errstr', GetLoadErrorStr <> '');
end.
