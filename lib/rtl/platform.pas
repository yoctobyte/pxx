unit platform;
{ Minimal Platform Abstraction Layer (PAL).

  This facade is platform-neutral. The implementation is selected by putting one
  backend directory (for example lib/rtl/platform/posix or lib/rtl/platform/esp)
  on the Pascal unit search path so `uses platform_backend` binds there. }

interface

uses platform_backend;

const
  PAL_STDIN  = 0;
  PAL_STDOUT = 1;
  PAL_STDERR = 2;

  PAL_PLATFORM_POSIX = 1;
  PAL_PLATFORM_ESP_IDF = 2;

  PAL_OPEN_READ   = 0;
  PAL_OPEN_WRITE  = 1;
  PAL_OPEN_RDWR   = 2;
  PAL_OPEN_CREATE = $40;
  PAL_OPEN_TRUNC  = $200;
  PAL_OPEN_APPEND = $400;

  PAL_ERR_UNSUPPORTED = -38; { Linux ENOSYS, used as the portable "not here" }

function PalPlatform: Integer;
function PalHasFiles: Boolean;
function PalHasSockets: Boolean;
function PalHasThreads: Boolean;
function PalHasDynlib: Boolean;

function PalUnsupported: Integer;

function PalOpen(path: PChar; flags, mode: Integer): Integer;
function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalClose(handle: Integer): Integer;

function PalMonotonicMillis: Int64;
procedure PalYield;

implementation

function PalPlatform: Integer;
begin
  Result := PalBackendPlatform;
end;

function PalHasFiles: Boolean;
begin
  Result := PalBackendHasFiles;
end;

function PalHasSockets: Boolean;
begin
  Result := PalBackendHasSockets;
end;

function PalHasThreads: Boolean;
begin
  Result := PalBackendHasThreads;
end;

function PalHasDynlib: Boolean;
begin
  Result := PalBackendHasDynlib;
end;

function PalUnsupported: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := PalBackendOpen(path, flags, mode);
end;

function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendRead(handle, buf, len);
end;

function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendWrite(handle, buf, len);
end;

function PalClose(handle: Integer): Integer;
begin
  Result := PalBackendClose(handle);
end;

function PalMonotonicMillis: Int64;
begin
  Result := PalBackendMonotonicMillis;
end;

procedure PalYield;
begin
  PalBackendYield;
end;

end.
