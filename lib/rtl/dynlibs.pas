unit dynlibs;
{ FPC-compatible `dynlibs` surface.

  Two modes, chosen at compile time:

  * Default (syscall-only, libc-free): there is no runtime loader, so this is an
    HONEST STUB — LoadLibrary returns NilHandle, GetProcedureAddress returns nil.
    Callers that treat a nil handle as "optional library unavailable" (e.g.
    SSL/TLS in Synapse) degrade correctly. This keeps the core libc-free.

  * Opt-in real loader (`-dPXX_DYNLIB_LIBC`): wraps libc's dlopen/dlsym/dlclose.
    The binary then links libc.so.6 (dynamic interp + GOT), the very dependency
    the syscall-only core avoids — so it is opt-in per project, like --mimic-fpc.
    First real consumer: loading .so files we don't control (OpenSSL etc.).
    Verified on x86-64; the cdecl extern + dynamic-link emission is target
    independent, so other targets follow once tested.

  See feature-real-dynlib-loader for the libc-vs-from-scratch-ELF-loader policy. }

interface

type
  { FPC: PtrInt-wide opaque handle. }
  TLibHandle = PtrInt;

const
  NilHandle: TLibHandle = 0;

{ Load a shared library by name. Real loader: dlopen; stub: always NilHandle.
  A PChar argument is accepted via the compiler's implicit PChar->string
  conversion, so FPC code passing a PChar (e.g. Synapse SynaFpc) compiles as-is. }
function LoadLibrary(const Name: string): TLibHandle;

{ Resolve a symbol in a loaded library. Real loader: dlsym; stub: always nil. }
function GetProcedureAddress(Lib: TLibHandle; const ProcName: string): Pointer;

{ Unload a library. Real loader: dlclose; stub: trivial success. }
function UnloadLibrary(Lib: TLibHandle): Boolean;

{ FPC aliases kept for source compatibility. }
function GetProcAddress(Lib: TLibHandle; const ProcName: string): Pointer;
function FreeLibrary(Lib: TLibHandle): Boolean;

{ Last loader error. }
function GetLoadErrorStr: string;

implementation

{$ifdef PXX_DYNLIB_LIBC}

const
  RTLD_NOW = 2;   { resolve all symbols at load time (Linux/glibc) }

{ dlopen/dlsym/dlclose live in libc.so.6 on modern glibc (>= 2.34; the old
  separate libdl is now an empty stub). The compiler emits the dynamic-link
  machinery (PT_INTERP, dynsym, GOT) for any `external '<soname>'` routine. }
function c_dlopen(name: PChar; flag: Integer): Pointer; cdecl; external 'libc.so.6' name 'dlopen';
function c_dlsym(handle: Pointer; symbol: PChar): Pointer; cdecl; external 'libc.so.6' name 'dlsym';
function c_dlclose(handle: Pointer): Integer; cdecl; external 'libc.so.6' name 'dlclose';

function LoadLibrary(const Name: string): TLibHandle;
begin
  Result := TLibHandle(c_dlopen(PChar(Name), RTLD_NOW));
end;

function GetProcedureAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  if Lib = NilHandle then Result := nil
  else Result := c_dlsym(Pointer(Lib), PChar(ProcName));
end;

function UnloadLibrary(Lib: TLibHandle): Boolean;
begin
  if Lib = NilHandle then Result := True
  else Result := c_dlclose(Pointer(Lib)) = 0;
end;

function GetLoadErrorStr: string;
begin
  Result := 'dynlibs: see dlerror (libc loader)';
end;

{$else}

function LoadLibrary(const Name: string): TLibHandle;
begin
  { No runtime loader on the libc-free target. NilHandle signals "unavailable",
    which well-behaved callers (Synapse) treat as an optional lib not present. }
  Result := NilHandle;
end;

function GetProcedureAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  Result := nil;
end;

function UnloadLibrary(Lib: TLibHandle): Boolean;
begin
  { Nothing was ever loaded; freeing a NilHandle is a no-op success. }
  Result := True;
end;

function GetLoadErrorStr: string;
begin
  Result := 'dynlibs: no runtime loader on this target (libc-free build)';
end;

{$endif}

function GetProcAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  Result := GetProcedureAddress(Lib, ProcName);
end;

function FreeLibrary(Lib: TLibHandle): Boolean;
begin
  Result := UnloadLibrary(Lib);
end;

end.
