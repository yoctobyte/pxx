unit dynlibs;
{ FPC-compatible `dynlibs` surface — HONEST STUB (feature-synapse-compile-check).

  libc-free POSIX has no runtime loader, so this unit cannot actually load a
  shared object: LoadLibrary returns NilHandle, GetProcedureAddress returns nil.
  That is the correct answer here, not a placeholder for a compiler bug — see
  lib/rtl/platform.pas (PalHasDynlib) and the recon notes.

  It exists so units that `uses dynlibs` (Synapse's SynaFpc, hence the whole
  Synapse leaf set) compile, and so the no-dynamic-lib path works: callers that
  treat a nil handle as "optional library unavailable" (e.g. SSL/TLS in Synapse)
  degrade correctly. The real loader is a separate, opt-in feature:
  feature-real-dynlib-loader (PalDlOpen/Sym/Close + a link-libc-vs-ELF-loader
  decision). Do NOT fake GetProcedureAddress until that lands. }

interface

type
  { FPC: PtrInt-wide opaque handle. }
  TLibHandle = PtrInt;

const
  NilHandle: TLibHandle = 0;

{ Load a shared library by name. No loader present -> always NilHandle. }
function LoadLibrary(const Name: string): TLibHandle;
{ WORKAROUND (bug-pchar-to-string-implicit-conv): FPC converts a PChar argument
  to the string param automatically, so its dynlibs needs no PChar overload.
  PXX's MatchProcCall does not yet, and Synapse's SynaFpc passes a PChar — so we
  add explicit PChar overloads here. REMOVE both once that Track A bug is fixed. }
function LoadLibrary(Name: PChar): TLibHandle;

{ Resolve a symbol in a loaded library. No loader present -> always nil. }
function GetProcedureAddress(Lib: TLibHandle; const ProcName: string): Pointer;
{ WORKAROUND (bug-pchar-to-string-implicit-conv) — remove with the one above. }
function GetProcedureAddress(Lib: TLibHandle; ProcName: PChar): Pointer;

{ Unload a library. Nothing was loaded -> succeeds trivially. }
function UnloadLibrary(Lib: TLibHandle): Boolean;

{ FPC aliases kept for source compatibility. }
function GetProcAddress(Lib: TLibHandle; const ProcName: string): Pointer;
function FreeLibrary(Lib: TLibHandle): Boolean;

{ Last loader error. No loader -> a fixed diagnostic. }
function GetLoadErrorStr: string;

implementation

function LoadLibrary(const Name: string): TLibHandle;
begin
  { No runtime loader on the libc-free target. NilHandle signals "unavailable",
    which well-behaved callers (Synapse) treat as an optional lib not present. }
  Result := NilHandle;
end;

function LoadLibrary(Name: PChar): TLibHandle;
begin
  Result := NilHandle;
end;

function GetProcedureAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  Result := nil;
end;

function GetProcedureAddress(Lib: TLibHandle; ProcName: PChar): Pointer;
begin
  Result := nil;
end;

function UnloadLibrary(Lib: TLibHandle): Boolean;
begin
  { Nothing was ever loaded; freeing a NilHandle is a no-op success. }
  Result := True;
end;

function GetProcAddress(Lib: TLibHandle; const ProcName: string): Pointer;
begin
  Result := GetProcedureAddress(Lib, ProcName);
end;

function FreeLibrary(Lib: TLibHandle): Boolean;
begin
  Result := UnloadLibrary(Lib);
end;

function GetLoadErrorStr: string;
begin
  Result := 'dynlibs: no runtime loader on this target (libc-free build)';
end;

end.
