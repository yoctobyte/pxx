{ SPDX-License-Identifier: Zlib }
unit dynlibs;
{ FPC-compatible `dynlibs` surface over the PAL dynamic-loader primitives
  (PalDlOpen/PalDlSym/PalDlClose — feature-real-dynlib-loader follow-up (a)).

  The loader policy lives in the PAL backend, not here:

  * Default (syscall-only, libc-free): the posix backend compiles honest
    stubs — LoadLibrary returns NilHandle, GetProcedureAddress returns nil,
    and PalHasDynlib is False. Callers that treat a nil handle as "optional
    library unavailable" (e.g. SSL/TLS in Synapse) degrade correctly.

  * Opt-in real loader (`-dPXX_DYNLIB_LIBC`): the posix backend wraps libc's
    dlopen/dlsym/dlclose. The binary then links libc.so.6 (dynamic interp +
    GOT), the very dependency the syscall-only core avoids — so it is opt-in
    per project, like --mimic-fpc. First real consumer: loading .so files we
    don't control (OpenSSL etc.). Verified on x86-64.

  ESP has no loader — always the stub shape. See feature-real-dynlib-loader
  for the libc-vs-from-scratch-ELF-loader policy. }

interface

uses platform;

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

function LoadLibrary(const Name: string): TLibHandle;
begin
  Result := TLibHandle(PalDlOpen(PChar(Name)));
end;

function GetProcedureAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  if Lib = NilHandle then Result := nil
  else Result := PalDlSym(Pointer(Lib), PChar(ProcName));
end;

function UnloadLibrary(Lib: TLibHandle): Boolean;
begin
  { Freeing a NilHandle (nothing loaded / stub) is a no-op success. }
  if Lib = NilHandle then Result := True
  else Result := PalDlClose(Pointer(Lib)) = 0;
end;

function GetLoadErrorStr: string;
begin
  if PalHasDynlib then
    Result := 'dynlibs: see dlerror (libc loader)'
  else
    Result := 'dynlibs: no runtime loader on this target (libc-free build; opt in with -dPXX_DYNLIB_LIBC)';
end;

function GetProcAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  Result := GetProcedureAddress(Lib, ProcName);
end;

function FreeLibrary(Lib: TLibHandle): Boolean;
begin
  Result := UnloadLibrary(Lib);
end;

end.
