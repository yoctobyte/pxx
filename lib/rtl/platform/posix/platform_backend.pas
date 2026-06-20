unit platform_backend;
{ POSIX PAL backend selected by -Fulib/rtl/platform/posix. }

interface

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendClose(handle: Integer): Integer;

function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;

implementation

const
  PAL_PLATFORM_POSIX = 1;

{$ifdef CPUX86_64}
  SYS_read = 0; SYS_write = 1; SYS_close = 3; SYS_openat = 257;
{$endif}
{$ifdef CPU_I386}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_openat = 295;
{$endif}
{$ifdef CPU_AARCH64}
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_openat = 56;
{$endif}
{$ifdef CPU_ARM32}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_openat = 322;
{$endif}
  PAL_AT_FDCWD = -100;

function PalBackendPlatform: Integer;
begin
  Result := PAL_PLATFORM_POSIX;
end;

function PalBackendHasFiles: Boolean;
begin
  Result := True;
end;

function PalBackendHasSockets: Boolean;
begin
  Result := True;
end;

function PalBackendHasThreads: Boolean;
begin
  Result := True;
end;

function PalBackendHasDynlib: Boolean;
begin
  Result := True;
end;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_openat, PAL_AT_FDCWD, Int64(path), flags, mode, 0, 0));
end;

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_read, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_write, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendClose(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_close, handle, 0, 0, 0, 0, 0));
end;

function PalBackendMonotonicMillis: Int64;
begin
  Result := 0;
end;

procedure PalBackendYield;
begin
end;

end.
